# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Create an issue on the configured issue tracker (GitHub/GitLab/Codeberg/Linear)
    #
    # Creates the issue via the provider API, then stores the issue URL, number,
    # and provider on the error record for linking.
    #
    # @example
    #   result = CreateIssue.call(error_id, dashboard_url: "https://app.com/error_dashboard/errors/42")
    #   result[:success]   # => true
    #   result[:issue_url] # => "https://github.com/user/repo/issues/42"
    class CreateIssue
      def self.call(error_id, dashboard_url: nil)
        new(error_id, dashboard_url: dashboard_url).call
      end

      def initialize(error_id, dashboard_url: nil)
        @error_id = error_id
        @dashboard_url = dashboard_url
      end

      def call
        error = ErrorLog.find(@error_id)

        # Don't create duplicate issues
        if error.external_issue_url.present?
          return { success: false, error: "Error already has a linked issue: #{error.external_issue_url}" }
        end

        client = Services::IssueTrackerClient.from_config
        return { success: false, error: "Issue tracking is not configured" } unless client

        config = RailsErrorDashboard.configuration
        title = "[#{error.error_type}] #{error.message.to_s.truncate(100)}"
        body = Services::IssueBodyFormatter.call(error, dashboard_url: @dashboard_url)
        labels = config.issue_tracker_labels || []

        result = client.create_issue(title: title, body: body, labels: labels)

        if result[:success]
          error.update!(
            external_issue_url: result[:url],
            external_issue_number: result[:number],
            external_issue_provider: config.effective_issue_tracker_provider.to_s
          )
          { success: true, issue_url: result[:url], issue_number: result[:number] }
        else
          { success: false, error: result[:error] }
        end
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Error not found: #{@error_id}" }
      rescue => e
        { success: false, error: "#{e.class}: #{e.message}" }
      end
    end
  end
end
