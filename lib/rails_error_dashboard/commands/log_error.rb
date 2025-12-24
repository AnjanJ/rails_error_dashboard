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

        error_log = ErrorLog.create!(
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
          occurred_at: Time.current
        )

        # Send notification asynchronously if configured
        notify_error(error_log) if should_notify?

        error_log
      rescue => e
        # Don't let error logging cause more errors
        Rails.logger.error("Failed to log error: #{e.message}")
        nil
      end

      private

      def should_notify?
        RailsErrorDashboard.configuration.slack_webhook_url.present?
      end

      def notify_error(error_log)
        SlackErrorNotificationJob.perform_later(error_log.id)
      end
    end
  end
end
