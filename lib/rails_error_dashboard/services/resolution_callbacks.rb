# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # What happens after an error has been marked resolved, whichever command
    # did it: the host's `notification_callbacks[:error_resolved]` lambdas
    # (the issue-tracker integration closes the linked issue from one of
    # these) and the `error_resolved.rails_error_dashboard` instrumentation
    # event.
    #
    # WHY ONE PLACE: only ResolveError ran these. An error resolved from the
    # batch toolbar, or through the status dropdown (UpdateErrorStatus),
    # stayed "resolved" on the dashboard with its GitHub or Linear issue still
    # open, and nothing subscribed to the event heard about it.
    #
    # Plugin hooks are deliberately not here: `:on_error_resolved` and
    # `:on_errors_batch_resolved` are separate events in the plugin API, and
    # each command dispatches its own.
    #
    # Each callback is rescued on its own, so one failing host lambda does
    # not stop the next, and never fails the resolution that already happened.
    class ResolutionCallbacks
      def self.call(error_log, resolved_by: nil)
        RailsErrorDashboard.configuration.notification_callbacks[:error_resolved].each do |callback|
          callback.call(error_log)
        rescue => e
          RailsErrorDashboard::Logger.error("Error in error_resolved callback: #{e.message}")
        end

        ActiveSupport::Notifications.instrument("error_resolved.rails_error_dashboard", {
          error_log: error_log,
          error_id: error_log.id,
          error_type: error_log.error_type,
          resolved_by: resolved_by,
          resolved_at: error_log.resolved_at
        })
        nil
      rescue => e
        RailsErrorDashboard::Logger.error("ResolutionCallbacks failed for error #{error_log&.id}: #{e.message}")
        nil
      end
    end
  end
end
