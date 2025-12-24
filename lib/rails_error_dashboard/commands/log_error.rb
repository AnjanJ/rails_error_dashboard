# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Log an error to the database
    # This is a write operation that creates an ErrorLog record
    class LogError
      def self.call(exception, context = {})
        new(exception, context).call
      end

      def initialize(exception, context = {})
        @exception = exception
        @context = context
      end

      def call
        error_context = ValueObjects::ErrorContext.new(@context, @context[:source])

        # Build error attributes
        attributes = {
          error_type: @exception.class.name,
          message: @exception.message,
          backtrace: @exception.backtrace&.join("\n"),
          user_id: error_context.user_id,
          request_url: error_context.request_url,
          request_params: error_context.request_params,
          user_agent: error_context.user_agent,
          ip_address: error_context.ip_address,
          environment: Rails.env,
          platform: error_context.platform,
          controller_name: error_context.controller_name,
          action_name: error_context.action_name,
          occurred_at: Time.current
        }

        # Generate error hash for deduplication (including controller/action context)
        error_hash = generate_error_hash(@exception, error_context.controller_name, error_context.action_name)

        # Find existing error or create new one
        # This ensures accurate occurrence tracking
        error_log = ErrorLog.find_or_increment_by_hash(error_hash, attributes.merge(error_hash: error_hash))

        # Send notifications only for new errors (not increments)
        # Check if this is first occurrence or error was just created
        send_notifications(error_log) if error_log.occurrence_count == 1

        error_log
      rescue => e
        # Don't let error logging cause more errors
        Rails.logger.error("Failed to log error: #{e.message}")
        Rails.logger.error("Backtrace: #{e.backtrace&.first(5)&.join("\n")}")
        nil
      end

      private

      # Generate consistent hash for error deduplication
      # Same hash = same error type
      # Note: This is also defined in ErrorLog model for backward compatibility
      def generate_error_hash(exception, controller_name = nil, action_name = nil)
        # Hash components:
        # 1. Error class (NoMethodError, ArgumentError, etc.)
        # 2. Normalized message (replace numbers, quoted strings)
        # 3. First stack frame file (ignore line numbers)
        # 4. Controller name (for context-aware grouping)
        # 5. Action name (for context-aware grouping)

        normalized_message = exception.message
          &.gsub(/\d+/, "N")                    # Replace numbers: "User 123" -> "User N"
          &.gsub(/"[^"]*"/, '""')               # Replace quoted strings: "foo" -> ""
          &.gsub(/'[^']*'/, "''")               # Replace single quoted strings
          &.gsub(/0x[0-9a-f]+/i, "0xHEX")       # Replace hex addresses
          &.gsub(/#<[^>]+>/, "#<OBJ>")          # Replace object inspections

        # Get first meaningful stack frame (skip gems, focus on app code)
        first_app_frame = exception.backtrace&.find { |frame|
          # Look for app code, not gems
          frame.include?("/app/") || frame.include?("/lib/") || !frame.include?("/gems/")
        }

        # Extract just the file path, not line number
        file_path = first_app_frame&.split(":")&.first

        # Generate hash including controller/action for better grouping
        digest_input = [
          exception.class.name,
          normalized_message,
          file_path,
          controller_name, # Context: which controller
          action_name      # Context: which action
        ].compact.join("|")

        Digest::SHA256.hexdigest(digest_input)[0..15]
      end

      def send_notifications(error_log)
        config = RailsErrorDashboard.configuration

        # Send Slack notification
        if config.enable_slack_notifications && config.slack_webhook_url.present?
          SlackErrorNotificationJob.perform_later(error_log.id)
        end

        # Send email notification
        if config.enable_email_notifications && config.notification_email_recipients.present?
          EmailErrorNotificationJob.perform_later(error_log.id)
        end

        # Send Discord notification
        if config.enable_discord_notifications && config.discord_webhook_url.present?
          DiscordErrorNotificationJob.perform_later(error_log.id)
        end

        # Send PagerDuty notification (critical errors only)
        if config.enable_pagerduty_notifications && config.pagerduty_integration_key.present?
          PagerdutyErrorNotificationJob.perform_later(error_log.id)
        end

        # Send webhook notifications
        if config.enable_webhook_notifications && config.webhook_urls.present?
          WebhookErrorNotificationJob.perform_later(error_log.id)
        end
      end
    end
  end
end
