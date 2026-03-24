# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Mute notifications for an error
    # Muted errors still appear in the dashboard but do not trigger any notifications.
    class MuteError
      def self.call(error_id, muted_by: nil, reason: nil)
        new(error_id, muted_by, reason).call
      end

      def initialize(error_id, muted_by, reason)
        @error_id = error_id
        @muted_by = muted_by
        @reason = reason
      end

      def call
        error = ErrorLog.find(@error_id)

        if @reason.present?
          error.comments.create!(
            author_name: @muted_by || "System",
            body: "Muted notifications: #{@reason}"
          )
        end

        error.update!(
          muted: true,
          muted_at: Time.current,
          muted_by: @muted_by,
          muted_reason: @reason
        )

        PluginRegistry.dispatch(:on_error_muted, error)
        error
      end
    end
  end
end
