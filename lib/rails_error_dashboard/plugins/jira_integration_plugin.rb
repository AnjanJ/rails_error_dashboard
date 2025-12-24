# frozen_string_literal: true

module RailsErrorDashboard
  module Plugins
    # Example plugin: Jira integration
    # Automatically creates Jira tickets for critical errors
    #
    # Usage:
    #   RailsErrorDashboard.register_plugin(
    #     RailsErrorDashboard::Plugins::JiraIntegrationPlugin.new(
    #       jira_url: ENV['JIRA_URL'],
    #       jira_username: ENV['JIRA_USERNAME'],
    #       jira_api_token: ENV['JIRA_API_TOKEN'],
    #       jira_project_key: ENV['JIRA_PROJECT_KEY'],
    #       only_critical: true
    #     )
    #   )
    #
    class JiraIntegrationPlugin < Plugin
      def initialize(jira_url: nil, jira_username: nil, jira_api_token: nil, jira_project_key: nil, only_critical: true)
        @jira_url = jira_url
        @jira_username = jira_username
        @jira_api_token = jira_api_token
        @jira_project_key = jira_project_key
        @only_critical = only_critical
      end

      def name
        "Jira Integration"
      end

      def description
        "Automatically creates Jira tickets for critical errors"
      end

      def version
        "1.0.0"
      end

      def enabled?
        @jira_url.present? && @jira_username.present? && @jira_api_token.present? && @jira_project_key.present?
      end

      def on_error_logged(error_log)
        return if @only_critical && !error_log.critical?

        create_jira_ticket(error_log)
      end

      private

      def create_jira_ticket(error_log)
        # Example Jira ticket creation
        # In production, you'd use the jira-ruby gem or make API calls directly

        ticket_data = {
          project: { key: @jira_project_key },
          summary: "[#{error_log.environment}] #{error_log.error_type}",
          description: build_description(error_log),
          issuetype: { name: "Bug" },
          priority: { name: jira_priority(error_log) },
          labels: [ "rails-error-dashboard", error_log.platform, error_log.environment ]
        }

        Rails.logger.info("Would create Jira ticket: #{ticket_data.to_json}")

        # Actual implementation:
        # require 'httparty'
        # response = HTTParty.post(
        #   "#{@jira_url}/rest/api/2/issue",
        #   basic_auth: { username: @jira_username, password: @jira_api_token },
        #   headers: { 'Content-Type' => 'application/json' },
        #   body: { fields: ticket_data }.to_json
        # )
      end

      def build_description(error_log)
        <<~DESC
          h2. Error Details

          *Error Type:* #{error_log.error_type}
          *Message:* #{error_log.message}
          *Platform:* #{error_log.platform}
          *Environment:* #{error_log.environment}
          *Severity:* #{error_log.severity}
          *Controller:* #{error_log.controller_name}
          *Action:* #{error_log.action_name}
          *First Seen:* #{error_log.first_seen_at}
          *Occurrences:* #{error_log.occurrence_count}

          h2. Backtrace

          {code}
          #{error_log.backtrace&.lines&.first(10)&.join}
          {code}

          h2. Dashboard Link

          [View in Dashboard|#{dashboard_url(error_log)}]
        DESC
      end

      def jira_priority(error_log)
        case error_log.severity.to_s
        when "critical"
          "Highest"
        when "high"
          "High"
        when "medium"
          "Medium"
        else
          "Low"
        end
      end

      def dashboard_url(error_log)
        base_url = RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000"
        "#{base_url}/error_dashboard/errors/#{error_log.id}"
      end
    end
  end
end
