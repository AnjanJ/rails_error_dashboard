# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::LinearIssueClient do
  let(:api_url) { "https://api.linear.app/graphql" }
  let(:client) { described_class.new(token: "lin_api_test", repo: "ENG") }

  def stub_graphql(matching, data: nil, errors: nil, status: 200)
    stub_request(:post, api_url)
      .with { |req| req.body.include?(matching) }
      .to_return(
        status: status,
        body: { data: data, errors: errors }.compact.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#create_issue" do
    def stub_team_lookup(nodes: [ { id: "team-uuid" } ])
      stub_graphql("teams(filter", data: { teams: { nodes: nodes } })
    end

    it "creates an issue in the configured team" do
      stub_team_lookup
      create_stub = stub_graphql("issueCreate", data: {
        issueCreate: {
          success: true,
          issue: { identifier: "ENG-42", number: 42, url: "https://linear.app/acme/issue/ENG-42/boom" }
        }
      })

      result = client.create_issue(title: "NoMethodError", body: "Error details", labels: [])
      expect(result[:success]).to be true
      expect(result[:url]).to eq("https://linear.app/acme/issue/ENG-42/boom")
      expect(result[:number]).to eq(42)
      expect(create_stub).to have_been_requested
    end

    it "resolves label names to ids and creates missing labels" do
      stub_team_lookup
      stub_graphql("issueLabels(filter", data: {
        issueLabels: { nodes: [ { id: "label-bug", name: "bug" } ] }
      })
      label_create_stub = stub_graphql("issueLabelCreate", data: {
        issueLabelCreate: { issueLabel: { id: "label-prod" } }
      })
      create_stub = stub_graphql("issueCreate", data: {
        issueCreate: { success: true, issue: { identifier: "ENG-7", number: 7, url: "https://linear.app/acme/issue/ENG-7/x" } }
      })

      result = client.create_issue(title: "Boom", body: "Details", labels: [ "bug", "production" ])
      expect(result[:success]).to be true
      expect(label_create_stub).to have_been_requested
      expect(create_stub).to have_been_requested
    end

    it "returns error when the team is not found" do
      stub_team_lookup(nodes: [])

      result = client.create_issue(title: "Boom", body: "Details", labels: [])
      expect(result[:success]).to be false
      expect(result[:error]).to include("team 'ENG' not found")
    end

    it "returns error on GraphQL errors" do
      stub_team_lookup
      stub_graphql("issueCreate", errors: [ { message: "Argument Validation Error" } ])

      result = client.create_issue(title: "Boom", body: "Details", labels: [])
      expect(result[:success]).to be false
      expect(result[:error]).to include("Argument Validation Error")
    end
  end

  describe "#close_issue" do
    it "moves the issue to the first completed-type workflow state" do
      stub_graphql("issue(id", data: { issue: { id: "issue-uuid" } })
      stub_graphql("workflowStates(filter", data: {
        workflowStates: { nodes: [
          { id: "state-todo", name: "Todo", type: "unstarted", position: 1 },
          { id: "state-done", name: "Done", type: "completed", position: 4 }
        ] }
      })
      update_stub = stub_graphql("issueUpdate", data: { issueUpdate: { success: true } })

      result = client.close_issue(number: 42)
      expect(result[:success]).to be true
      expect(update_stub).to have_been_requested
      expect(WebMock).to have_requested(:post, api_url)
        .with { |req| req.body.include?("issueUpdate") && req.body.include?("state-done") }
    end
  end

  describe "#reopen_issue" do
    it "moves the issue to the first unstarted-type workflow state" do
      stub_graphql("issue(id", data: { issue: { id: "issue-uuid" } })
      stub_graphql("workflowStates(filter", data: {
        workflowStates: { nodes: [
          { id: "state-backlog", name: "Backlog", type: "backlog", position: 0 },
          { id: "state-todo", name: "Todo", type: "unstarted", position: 1 },
          { id: "state-done", name: "Done", type: "completed", position: 4 }
        ] }
      })
      stub_graphql("issueUpdate", data: { issueUpdate: { success: true } })

      result = client.reopen_issue(number: 42)
      expect(result[:success]).to be true
      expect(WebMock).to have_requested(:post, api_url)
        .with { |req| req.body.include?("issueUpdate") && req.body.include?("state-todo") }
    end
  end

  describe "#add_comment" do
    it "creates a comment on the issue" do
      stub_graphql("issue(id", data: { issue: { id: "issue-uuid" } })
      stub_graphql("commentCreate", data: {
        commentCreate: { success: true, comment: { url: "https://linear.app/acme/issue/ENG-42#comment-1" } }
      })

      result = client.add_comment(number: 42, body: "Error recurred")
      expect(result[:success]).to be true
      expect(result[:url]).to include("comment")
    end
  end

  describe "#fetch_comments" do
    it "returns formatted comments addressed by identifier" do
      stub_graphql("comments(first", data: {
        issue: {
          comments: { nodes: [
            {
              body: "Looking into this",
              createdAt: "2026-06-12T10:00:00.000Z",
              url: "https://linear.app/acme/issue/ENG-42#comment-1",
              user: { name: "Dev One", avatarUrl: "https://avatar.url/1" }
            }
          ] }
        }
      })

      result = client.fetch_comments(number: 42)
      expect(result[:success]).to be true
      expect(result[:comments].size).to eq(1)
      expect(result[:comments].first[:author]).to eq("Dev One")
      expect(WebMock).to have_requested(:post, api_url)
        .with { |req| req.body.include?("ENG-42") }
    end
  end

  describe "#fetch_issue" do
    it "maps completed state type to closed" do
      stub_graphql("state { name type }", data: {
        issue: {
          title: "NoMethodError",
          state: { name: "Done", type: "completed" },
          assignee: { name: "Dev One", avatarUrl: "https://avatar.url/1" },
          labels: { nodes: [ { name: "bug", color: "#ff0000" } ] }
        }
      })

      result = client.fetch_issue(number: 42)
      expect(result[:success]).to be true
      expect(result[:state]).to eq("closed")
      expect(result[:assignees]).to eq([ { login: "Dev One", avatar_url: "https://avatar.url/1" } ])
      expect(result[:labels]).to eq([ { name: "bug", color: "ff0000" } ])
    end

    it "maps non-terminal state types to open" do
      stub_graphql("state { name type }", data: {
        issue: { title: "Boom", state: { name: "In Progress", type: "started" }, assignee: nil, labels: { nodes: [] } }
      })

      result = client.fetch_issue(number: 42)
      expect(result[:state]).to eq("open")
      expect(result[:assignees]).to eq([])
    end
  end

  describe "authentication" do
    it "sends personal API keys bare" do
      stub = stub_request(:post, api_url)
        .with(headers: { "Authorization" => "lin_api_test" })
        .to_return(status: 200, body: { data: { issue: { id: "x" } } }.to_json)

      client.send(:graphql, "query { viewer { id } }")
      expect(stub).to have_been_requested
    end

    it "sends OAuth tokens with a Bearer prefix" do
      oauth_client = described_class.new(token: "oauth-token", repo: "ENG")
      stub = stub_request(:post, api_url)
        .with(headers: { "Authorization" => "Bearer oauth-token" })
        .to_return(status: 200, body: { data: {} }.to_json)

      oauth_client.send(:graphql, "query { viewer { id } }")
      expect(stub).to have_been_requested
    end
  end

  describe "custom API URL" do
    it "uses the custom endpoint" do
      custom = described_class.new(token: "lin_api_x", repo: "OPS", api_url: "https://linear.example.com/graphql")
      stub = stub_request(:post, "https://linear.example.com/graphql")
        .to_return(status: 200, body: { data: { teams: { nodes: [] } } }.to_json)

      custom.create_issue(title: "T", body: "B", labels: [])
      expect(stub).to have_been_requested
    end
  end

  describe "network error handling" do
    it "returns error on timeout" do
      stub_request(:post, api_url).to_timeout

      result = client.create_issue(title: "Test", body: "Body", labels: [])
      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end
  end
end
