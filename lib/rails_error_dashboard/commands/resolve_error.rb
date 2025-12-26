# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Mark an error as resolved
    # This is a write operation that updates an ErrorLog record
    class ResolveError
      def self.call(error_id, resolution_data = {})
        new(error_id, resolution_data).call
      end

      def initialize(error_id, resolution_data = {})
        @error_id = error_id
        @resolution_data = resolution_data
      end

      def call
        error = ErrorLog.find(@error_id)

        error.update!(
          resolved: true,
          resolved_at: Time.current,
          resolved_by_name: @resolution_data[:resolved_by_name],
          resolution_comment: @resolution_data[:resolution_comment],
          resolution_reference: @resolution_data[:resolution_reference]
        )

        # Dispatch plugin event for resolved error
        PluginRegistry.dispatch(:on_error_resolved, error)

        # Trigger notification callbacks
        RailsErrorDashboard.configuration.notification_callbacks[:error_resolved].each do |callback|
          callback.call(error)
        rescue => e
          RailsErrorDashboard::Logger.error("Error in error_resolved callback: #{e.message}")
        end

        # Emit ActiveSupport::Notifications instrumentation event
        ActiveSupport::Notifications.instrument("error_resolved.rails_error_dashboard", {
          error_log: error,
          error_id: error.id,
          error_type: error.error_type,
          resolved_by: @resolution_data[:resolved_by_name],
          resolved_at: error.resolved_at
        })

        error
      end
    end
  end
end
