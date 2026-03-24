# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Unmute notifications for an error
    # Restores normal notification behavior for the error.
    class UnmuteError
      def self.call(error_id)
        new(error_id).call
      end

      def initialize(error_id)
        @error_id = error_id
      end

      def call
        error = ErrorLog.find(@error_id)
        error.update!(
          muted: false,
          muted_at: nil,
          muted_by: nil,
          muted_reason: nil
        )

        PluginRegistry.dispatch(:on_error_unmuted, error)
        error
      end
    end
  end
end
