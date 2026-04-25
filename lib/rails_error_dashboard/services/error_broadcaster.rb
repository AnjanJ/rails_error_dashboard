# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Infrastructure service: Turbo Stream broadcasting for real-time UI updates
    #
    # Handles broadcasting new errors, error updates, and stats refreshes
    # via Turbo Streams. Safely no-ops when Turbo/ActionCable is unavailable.
    #
    # IMPORTANT: Broadcasting failures MUST NOT block error logging.
    # All public methods rescue exceptions and log them.
    #
    # NOTE: Turbo broadcasts render partials via ApplicationController.render,
    # which is the HOST app's controller — engine route helpers (error_path, etc.)
    # are NOT available there. We render via the engine's own controller renderer
    # and pass pre-rendered HTML to the broadcast to ensure route helpers work.
    class ErrorBroadcaster
      # Broadcast a new error (prepend to error list + refresh stats)
      # @param error_log [ErrorLog] The newly created error
      def self.broadcast_new(error_log)
        return unless error_log
        return unless available?

        platforms = ErrorLog.distinct.pluck(:platform).compact
        show_platform = platforms.size > 1

        html = render_partial("rails_error_dashboard/errors/error_row",
          error: error_log, show_platform: show_platform)

        Turbo::StreamsChannel.broadcast_prepend_to(
          "error_list",
          target: "error_list",
          html: html
        )
        broadcast_stats
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast new error: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Broadcast an error update (replace in error list + refresh stats)
      # @param error_log [ErrorLog] The updated error
      def self.broadcast_update(error_log)
        return unless error_log
        return unless available?

        platforms = ErrorLog.distinct.pluck(:platform).compact
        show_platform = platforms.size > 1

        html = render_partial("rails_error_dashboard/errors/error_row",
          error: error_log, show_platform: show_platform)

        Turbo::StreamsChannel.broadcast_replace_to(
          "error_list",
          target: "error_#{error_log.id}",
          html: html
        )
        broadcast_stats
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast error update: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Broadcast stats refresh
      def self.broadcast_stats
        return unless available?

        stats = Queries::DashboardStats.call
        return unless stats.is_a?(Hash) && stats.present?

        html = render_partial("rails_error_dashboard/errors/stats", stats: stats)

        Turbo::StreamsChannel.broadcast_replace_to(
          "error_list",
          target: "dashboard_stats",
          html: html
        )
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast stats update: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Render a partial using the engine's controller renderer.
      # This ensures engine route helpers (error_path, etc.) are available,
      # unlike Turbo's default ApplicationController.render which uses the host app's context.
      def self.render_partial(partial, **locals)
        RailsErrorDashboard::ApplicationController.render(
          partial: partial,
          locals: locals
        )
      end

      # Check if broadcasting infrastructure is available.
      # Returns false when Turbo/ActionCable isn't loaded, or when the
      # ActionCable pubsub adapter can't be reached (e.g., Redis down).
      # Uses a 60-second cooldown after failure to avoid hammering a
      # dead Redis on every error (issue #114).
      # @return [Boolean]
      def self.available?
        return false unless defined?(Turbo)
        return false unless defined?(ActionCable)

        # Circuit breaker: skip broadcast attempts for 60s after a failure
        if @broadcast_unavailable_until && Time.current < @broadcast_unavailable_until
          return false
        end

        # Verify the pubsub adapter is reachable — without this,
        # broadcast_* calls attempt Redis and fail loudly when it's down
        server = ActionCable.server
        return false unless server.respond_to?(:pubsub)

        server.pubsub
        @broadcast_unavailable_until = nil
        true
      rescue => e
        @broadcast_unavailable_until = Time.current + 60
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Broadcast not available (pausing 60s): #{e.message}")
        false
      end
    end
  end
end
