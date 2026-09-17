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
      # Minimum seconds between two stats broadcasts on one stream, per process.
      # The row broadcasts are cheap (one partial); the stats payload is a full
      # DashboardStats computation, and a capture runs it from inside the host
      # app's request thread. Leading edge: the first event in a window
      # broadcasts, later ones are dropped and corrected by the next window or
      # the next page load.
      STATS_BROADCAST_INTERVAL = 5

      # Stream names, in ONE place for the view (turbo_stream_from) and for this
      # class. Three kinds, because a Turbo subscription is all-or-nothing per
      # stream and the index needs them separately: a view filtered by platform
      # wants row REPLACES (harmless: they only touch rows already on the page)
      # but not PREPENDS (a new row may not match its filter).
      #
      # Every kind exists globally and per application ("error_list_app_7"), so
      # a view filtered to one application never receives another's rows.
      STREAMS = { list: "error_list", updates: "error_updates", stats: "error_stats" }.freeze

      # Column visibility (which optional cells a row has) used to be two
      # SELECT DISTINCT scans per broadcast. It changes about never.
      COLUMN_VISIBILITY_TTL = 60.seconds

      # One throttle entry per stats stream, i.e. per application. Bounded so a
      # host with thousands of applications cannot grow it without limit.
      MAX_THROTTLED_STREAMS = 200

      THROTTLE_MUTEX = Mutex.new
      private_constant :THROTTLE_MUTEX

      # @param kind [Symbol] :list (new rows), :updates (row replaces) or :stats
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
        kinds = filtered ? %i[updates stats] : %i[list updates stats]
        kinds.map { |kind| stream_name(kind, application_id) }
      end

      # Broadcast a new error (prepend to error list + refresh stats)
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
        broadcast_stats(error_log.application_id)
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast new error: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Broadcast an error update (replace in error list + refresh stats)
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
        broadcast_stats(error_log.application_id)
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast error update: #{e.class} - #{e.message}")
        Rails.logger.debug("[RailsErrorDashboard] Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      end

      # Broadcast a stats refresh: all-application stats to the global stream,
      # application-scoped stats to that application's stream.
      #
      # ONE event computes at most ONE payload. Each stream is throttled on its
      # own (STATS_BROADCAST_INTERVAL); when both are due, the one that has
      # waited longest goes and the other is served by the next event. Computing
      # both would double the most expensive thing a capture does, and a
      # fixed order would starve the second stream whenever events are rare.
      #
      # @param application_id [Integer, nil] the application of the event, if any
      def self.broadcast_stats(application_id = nil)
        return unless available?
        return unless calm?

        scope = claim_stats_window!([ nil, application_id.presence ].uniq)
        return if scope == :none

        stats = scope ? Queries::DashboardStats.call(application_id: scope) : Queries::DashboardStats.call
        return unless stats.is_a?(Hash) && stats.present?

        html = render_partial("rails_error_dashboard/errors/stats", stats: stats)

        Turbo::StreamsChannel.broadcast_replace_to(
          stream_name(:stats, scope),
          target: "dashboard_stats",
          html: html
        )
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] Failed to broadcast stats update: #{e.class} - #{e.message}")
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

      # Picks which stats scope this event may broadcast, and claims its window.
      #
      # @param scopes [Array<Integer, nil>] candidate scopes (nil = all applications)
      # @return [Integer, nil, :none] the claimed scope, or :none when every
      #   candidate is still inside its window
      #
      # The claim is taken BEFORE the stats are computed, so concurrent captures
      # cannot all decide to compute at once, and a computation that fails does
      # not get retried by every event that follows it.
      def self.claim_stats_window!(scopes = [ nil ])
        THROTTLE_MUTEX.synchronize do
          @stats_claimed_at ||= {}
          now = monotonic_now

          due = scopes.select do |scope|
            last = @stats_claimed_at[scope]
            last.nil? || (now - last) >= STATS_BROADCAST_INTERVAL
          end
          return :none if due.empty?

          # Longest-waiting first; never-claimed counts as waiting forever.
          # min_by is stable, so the global stream wins a tie.
          chosen = due.min_by { |scope| @stats_claimed_at[scope] || -Float::INFINITY }
          @stats_claimed_at[chosen] = now

          if @stats_claimed_at.size > MAX_THROTTLED_STREAMS
            stalest = @stats_claimed_at.min_by { |_scope, at| at }.first
            @stats_claimed_at.delete(stalest)
          end

          chosen
        end
      end

      def self.throttled_stream_count
        THROTTLE_MUTEX.synchronize { (@stats_claimed_at || {}).size }
      end

      def self.monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # For specs and for a forked worker that wants a clean slate.
      def self.reset_throttle!
        THROTTLE_MUTEX.synchronize { @stats_claimed_at = {} }
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
      rescue LoadError, StandardError => e
        @broadcast_unavailable_until = Time.current + 60
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Broadcast not available (pausing 60s): #{e.message}")
        false
      end
    end
  end
end
