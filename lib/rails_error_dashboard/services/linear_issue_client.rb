# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Linear GraphQL API client for issue management.
    #
    # API Docs: https://developers.linear.app/docs/graphql/working-with-the-graphql-api
    # Auth: Personal API key (Settings > Security & access > Personal API keys)
    # Rate limit: 1,500 requests/hour per API key
    #
    # Unlike the git forges, Linear has no "owner/repo" — issues belong to a
    # team. The `repo` argument holds the team key (e.g. "ENG"), and issues
    # are addressed by their human identifier ("ENG-123"), reconstructed from
    # the team key plus the team-scoped issue number we store.
    #
    # Linear also has no open/closed binary — issues move between typed
    # workflow states. Closing maps to the team's first `completed`-type
    # state, reopening to the first `unstarted` (or `backlog`) state.
    class LinearIssueClient < IssueTrackerClient
      REOPEN_STATE_TYPES = [ "unstarted", "backlog", "triage" ].freeze

      def initialize(token:, repo:, api_url: nil)
        super
        @api_url = api_url || "https://api.linear.app/graphql"
      end

      def create_issue(title:, body:, labels: [])
        return error_response(@last_error || "Linear team '#{@repo}' not found") unless team_id

        input = { teamId: team_id, title: title, description: truncate_body(body) }
        label_ids = resolve_label_ids(labels)
        input[:labelIds] = label_ids if label_ids.any?

        data = graphql(<<~GRAPHQL, input: input)
          mutation($input: IssueCreateInput!) {
            issueCreate(input: $input) { success issue { identifier number url } }
          }
        GRAPHQL

        issue = data&.dig("issueCreate", "issue")
        if issue
          success_response(url: issue["url"], number: issue["number"])
        else
          error_response(@last_error || "Linear API error: issue creation failed")
        end
      end

      def close_issue(number:)
        update_issue_state(number, "completed")
      end

      def reopen_issue(number:)
        update_issue_state(number, REOPEN_STATE_TYPES)
      end

      def add_comment(number:, body:)
        issue_id = find_issue_id(number)
        return error_response(@last_error || "Linear issue #{identifier_for(number)} not found") unless issue_id

        data = graphql(<<~GRAPHQL, input: { issueId: issue_id, body: truncate_body(body) })
          mutation($input: CommentCreateInput!) {
            commentCreate(input: $input) { success comment { url } }
          }
        GRAPHQL

        comment = data&.dig("commentCreate", "comment")
        comment ? success_response(url: comment["url"]) : error_response(@last_error || "Linear API error: comment failed")
      end

      def fetch_comments(number:, per_page: 10)
        data = graphql(<<~GRAPHQL, id: identifier_for(number), first: per_page)
          query($id: String!, $first: Int!) {
            issue(id: $id) {
              comments(first: $first) {
                nodes { body createdAt url user { name avatarUrl } }
              }
            }
          }
        GRAPHQL

        nodes = data&.dig("issue", "comments", "nodes")
        return error_response(@last_error || "Linear API error: could not fetch comments") unless nodes

        comments = nodes.map { |c|
          {
            author: c.dig("user", "name"),
            avatar_url: c.dig("user", "avatarUrl"),
            body: c["body"],
            created_at: c["createdAt"],
            url: c["url"]
          }
        }
        success_response(comments: comments)
      end

      def fetch_issue(number:)
        data = graphql(<<~GRAPHQL, id: identifier_for(number))
          query($id: String!) {
            issue(id: $id) {
              title
              state { name type }
              assignee { name avatarUrl }
              labels { nodes { name color } }
            }
          }
        GRAPHQL

        issue = data&.dig("issue")
        return error_response(@last_error || "Linear API error: could not fetch issue") unless issue

        assignee = issue["assignee"]
        success_response(
          state: closed_state_type?(issue.dig("state", "type")) ? "closed" : "open",
          title: issue["title"],
          assignees: assignee ? [ { login: assignee["name"], avatar_url: assignee["avatarUrl"] } ] : [],
          labels: (issue.dig("labels", "nodes") || []).map { |l|
            { name: l["name"], color: l["color"]&.delete("#") }
          }
        )
      end

      private

      # Linear issues are addressed by "TEAM-123" — team key + stored number
      def identifier_for(number)
        "#{@repo}-#{number}"
      end

      def closed_state_type?(state_type)
        [ "completed", "canceled" ].include?(state_type)
      end

      def update_issue_state(number, state_types)
        issue_id = find_issue_id(number)
        return error_response(@last_error || "Linear issue #{identifier_for(number)} not found") unless issue_id

        state_id = workflow_state_id(Array(state_types))
        return error_response(@last_error || "No matching workflow state for #{Array(state_types).join('/')}") unless state_id

        data = graphql(<<~GRAPHQL, id: issue_id, input: { stateId: state_id })
          mutation($id: String!, $input: IssueUpdateInput!) {
            issueUpdate(id: $id, input: $input) { success }
          }
        GRAPHQL

        data&.dig("issueUpdate", "success") ? success_response({}) : error_response(@last_error || "Linear API error: state update failed")
      end

      def find_issue_id(number)
        data = graphql("query($id: String!) { issue(id: $id) { id } }", id: identifier_for(number))
        data&.dig("issue", "id")
      end

      def team_id
        @team_id ||= begin
          data = graphql(<<~GRAPHQL, key: @repo)
            query($key: String!) {
              teams(filter: { key: { eq: $key } }) { nodes { id } }
            }
          GRAPHQL
          data&.dig("teams", "nodes", 0, "id")
        end
      end

      # Pick the first workflow state whose type matches, in preference order
      def workflow_state_id(preferred_types)
        states = workflow_states
        return nil unless states

        preferred_types.each do |type|
          match = states.find { |s| s["type"] == type }
          return match["id"] if match
        end
        nil
      end

      def workflow_states
        @workflow_states ||= begin
          data = graphql(<<~GRAPHQL, key: @repo)
            query($key: String!) {
              workflowStates(filter: { team: { key: { eq: $key } } }) {
                nodes { id name type position }
              }
            }
          GRAPHQL
          data&.dig("workflowStates", "nodes")&.sort_by { |s| s["position"].to_f }
        end
      end

      # Best-effort: resolve label names to UUIDs, creating missing ones.
      # Label failures must never block issue creation.
      def resolve_label_ids(names)
        names = Array(names).map(&:to_s).reject(&:empty?)
        return [] if names.empty?

        data = graphql(<<~GRAPHQL, names: names)
          query($names: [String!]) {
            issueLabels(filter: { name: { in: $names } }) { nodes { id name } }
          }
        GRAPHQL
        existing = data&.dig("issueLabels", "nodes") || []
        ids = existing.map { |l| l["id"] }

        missing = names - existing.map { |l| l["name"] }
        missing.each do |name|
          created = graphql(<<~GRAPHQL, input: { name: name, teamId: team_id })
            mutation($input: IssueLabelCreateInput!) {
              issueLabelCreate(input: $input) { issueLabel { id } }
            }
          GRAPHQL
          id = created&.dig("issueLabelCreate", "issueLabel", "id")
          ids << id if id
        end

        ids
      rescue
        []
      end

      # Execute a GraphQL request. Returns the "data" hash, or nil on any
      # error (with the message stashed in @last_error for the caller).
      def graphql(query, variables = {})
        @last_error = nil
        response = http_post(@api_url, { query: query, variables: variables }, auth_headers)

        if response[:status] != 200
          message = response.dig(:body, "errors", 0, "message") || response[:error]
          @last_error = "Linear API error (#{response[:status]}): #{message}"
          return nil
        end

        errors = response.dig(:body, "errors")
        if errors.present?
          @last_error = "Linear API error: #{errors.first["message"]}"
          return nil
        end

        response.dig(:body, "data")
      end

      def auth_headers
        # Personal API keys are passed bare; OAuth tokens need a Bearer prefix
        value = @token.to_s.start_with?("lin_api_") ? @token : "Bearer #{@token}"
        { "Authorization" => value }
      end
    end
  end
end
