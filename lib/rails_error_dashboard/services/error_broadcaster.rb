# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Infrastructure service: Turbo Stream broadcasting for real-time UI updates
    #
    # Handles broadcasting new errors and error updates via Turbo Streams.
    # Safely no-ops when Turbo/ActionCable is unavailable.
    #
    # IMPORTANT: Broadcasting failures MUST NOT block error logging.
    # All public methods rescue exceptions and log them.
    #
    # NOTE: Turbo broadcasts render partials via ApplicationController.render,
    # which is the HOST app's controller — engine route helpers (error_path, etc.)
    # are NOT available there. We render via the engine's own controller renderer
    # and pass pre-rendered HTML to the broadcast to ensure route helpers work.
    class ErrorBroadcaster
      # Stream names, in ONE place for the view (turbo_stream_from) and for this
      # class. Two kinds, because a Turbo subscription is all-or-nothing per
      # stream and the index needs them separately: a view filtered by platform
      # wants row REPLACES (harmless: they only touch rows already on the page)
      # but not PREPENDS (a new row may not match its filter).
      #
      # Every kind exists globally and per application ("error_list_app_7"), so
      # a view filtered to one application never receives another's rows.
      #
      # There is no stats stream: no built-in page has a stats target, and the
      # payload was a full DashboardStats computation on the capture path.
      STREAMS = { list: "error_list", updates: "error_updates" }.freeze

      # Column visibility (which optional cells a row has) used to be two
      # SELECT DISTINCT scans per broadcast. It changes about never.
      COLUMN_VISIBILITY_TTL = 60.seconds

      # @param kind [Symbol] :list (new rows) or :updates (row replaces)
      # @param application_id [Integer, String, nil] nil/blank for the global stream
      # @return [String]
      def self.stream_name(kind, application_id = nil)
        base = STREAMS.fetch(kind)
        return base if application_id.blank?

        # to_i: the id reaches here from a request parameter in the view.
        "#{base}_app_#{application_id.to_s[/\A\d+\z/].to_i}"
      end

      # The streams a dashboard index page subscribes to.
      # @param application_id [Integer, String, nil] the page's application filter
      # @param filtered [Boolean] any OTHER filter, a sort or a later page is active,
      #   so a new row cannot simply be put on top of the list
      # @return [Array<String>]
      def self.streams_for_view(application_id: nil, filtered: false)
        kinds = filtered ? %i[updates] : %i[list updates]
        kinds.map { |kind| stream_name(kind, application_id) }
      end

      # Broadcast a new error (prepend to the error list)
      # @param error_log [ErrorLog] The newly created error
      def self.broadcast_new(error_log)
        return unless error_log
        return unless available?
        return unless calm?

        each_row_html(error_log) do |application_id, html|
          Turbo::StreamsChannel.broadcast_prepend_to(
            stream_name(:list, application_id),
            target: "error_list",
            html: html
          )
        end
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast new error: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Broadcast an error update (replace its row in the error list)
      # @param error_log [ErrorLog] The updated error
      def self.broadcast_update(error_log)
        return unless error_log
        return unless available?
        return unless calm?

        each_row_html(error_log) do |application_id, html|
          Turbo::StreamsChannel.broadcast_replace_to(
            stream_name(:updates, application_id),
            target: "error_#{error_log.id}",
            html: html
          )
        end
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast error update: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Yields [application_id_or_nil, row_html] once per row stream. The global
      # table has an Application column when there is more than one application;
      # an application's own table never does, so the two need different cells.
      # Rendered once when they come out the same.
      def self.each_row_html(error_log)
        render = lambda do |visibility, show_application|
          render_partial("rails_error_dashboard/errors/error_row",
            error: error_log, show_platform: visibility[:platform],
            show_environment: visibility[:environment], show_application: show_application)
        end

        global = column_visibility(nil)
        yield nil, render.call(global, global[:application])

        application_id = error_log.application_id
        return if application_id.blank?

        yield application_id, render.call(column_visibility(application_id), false)
      end

      # Which optional columns the index table shows, for the global view or for
      # one application -- the same rule the index itself applies. Cached for
      # COLUMN_VISIBILITY_TTL and keyed on the cache generation, so a user
      # action that could change it (a batch delete) refreshes it at once.
      def self.column_visibility(application_id)
        key = [ "red/columns", AnalyticsCacheManager.generation, application_id || "all" ].join("/")

        Rails.cache.fetch(key, expires_in: COLUMN_VISIBILITY_TTL) do
          scope = application_id ? ErrorLog.where(application_id: application_id) : ErrorLog.all
          {
            platform: scope.distinct.pluck(:platform).compact.size > 1,
            environment: ErrorLog.column_names.include?("environment") &&
              scope.distinct.pluck(:environment).compact.size > 1,
            application: application_id.nil? && Application.count > 1
          }
        end
      end

      # Live updates are a convenience; during a storm they are load. While the
      # breaker is anything but :closed nothing is broadcast -- the page catches
      # up on its next load. Fails towards broadcasting: Gate.state itself
      # answers :closed when storm protection is off or unreadable.
      def self.calm?
        StormProtection::Gate.state == :closed
      rescue StandardError
        true
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

      # Check if live updates are switched on and the broadcasting
      # infrastructure is available. The one gate for both ends: the ErrorLog
      # commit callbacks reach it through broadcast_*, and the index asks it
      # before rendering stream tags, so the two cannot disagree.
      # Returns false when config.enable_live_updates is off (the default:
      # broadcasting runs on the capture path), when Turbo/ActionCable isn't
      # loaded, or when the ActionCable pubsub adapter can't be reached (e.g.,
      # Redis down). Uses a 60-second cooldown after failure to avoid
      # hammering a dead Redis on every error (issue #114).
      # @return [Boolean]
      def self.available?
        return false unless RailsErrorDashboard.configuration.enable_live_updates
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
      rescue LoadError, StandardError => e
        @broadcast_unavailable_until = Time.current + 60
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Broadcast not available (pausing 60s): #{e.message}")
        false
      end
    end
  end
end
