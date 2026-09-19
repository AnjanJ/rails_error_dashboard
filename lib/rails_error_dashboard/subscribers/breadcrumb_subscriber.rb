# frozen_string_literal: true

module RailsErrorDashboard
  module Subscribers
    # Registers ActiveSupport::Notifications subscribers for breadcrumb collection.
    #
    # Each subscriber appends breadcrumbs to the thread-local ring buffer via
    # BreadcrumbCollector.add. The subscribers are registered once at boot when
    # enable_breadcrumbs is true.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Every subscriber wrapped in rescue => e; nil
    # - Never raise from subscriber callbacks
    # - Skip if buffer is nil (not in a request context)
    # - Filter out internal gem queries to avoid recursion
    class BreadcrumbSubscriber
      SQL_MESSAGE_MAX = 200

      # Event subscriptions managed by this class
      @subscriptions = []

      class << self
        attr_reader :subscriptions

        # Register all breadcrumb subscribers
        # @return [Array] Array of subscription objects
        def subscribe!
          @subscriptions = []

          @subscriptions << subscribe_sql
          @subscriptions << subscribe_controller
          @subscriptions << subscribe_cache_read
          @subscriptions << subscribe_cache_write
          @subscriptions << subscribe_job
          @subscriptions << subscribe_mailer
          @subscriptions << subscribe_deprecation

          @subscriptions
        end

        # Open a breadcrumb buffer around every Active Job perform, so a job
        # that fails outside a request still has an activity trail.
        #
        # Idempotent: the callback list belongs to ActiveJob::Base, and a
        # second registration would open and close the buffer twice per job.
        #
        # The config check is INSIDE the callback, not around this method.
        # enable_breadcrumbs defaults to false and the callback list is fixed
        # once the class loads, so gating registration would permanently
        # disable job breadcrumbs for any host that enables the feature in an
        # initializer running after the engine's.
        # @return [Boolean] true when the callback was installed
        def install_job_buffer!
          return false if @job_buffer_installed
          return false unless defined?(ActiveJob::Base)

          @job_buffer_installed = true
          ActiveSupport.on_load(:active_job) do
            around_perform do |_job, block|
              collector = RailsErrorDashboard::Services::BreadcrumbCollector
              owned =
                if RailsErrorDashboard.configuration.enable_breadcrumbs
                  collector.init_buffer_unless_present
                else
                  false
                end

              begin
                block.call
              ensure
                # ensure, always: a worker pool reuses threads, and a
                # thread-local left behind would leak one job's trail into the
                # next (safety rule 4).
                collector.clear_buffer_if_owned(owned)
              end
            end
          end
          true
        rescue StandardError => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] install_job_buffer! failed: #{e.class} - #{e.message}"
          )
          false
        end

        # Remove all breadcrumb subscribers
        def unsubscribe!
          @subscriptions.each do |sub|
            ActiveSupport::Notifications.unsubscribe(sub) if sub
          rescue => e
            nil
          end
          @subscriptions = []
        end

        private

        def subscribe_sql
          ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_sql(event)
          rescue => e
            nil
          end
        end

        def subscribe_controller
          ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_controller(event)
          rescue => e
            nil
          end
        end

        def subscribe_cache_read
          ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_cache(event, "read")
          rescue => e
            nil
          end
        end

        def subscribe_cache_write
          ActiveSupport::Notifications.subscribe("cache_write.active_support") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_cache(event, "write")
          rescue => e
            nil
          end
        end

        def subscribe_job
          ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_job(event)
          rescue => e
            nil
          end
        end

        def subscribe_mailer
          ActiveSupport::Notifications.subscribe("deliver.action_mailer") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_mailer(event)
          rescue => e
            nil
          end
        end

        def subscribe_deprecation
          ActiveSupport::Notifications.subscribe("deprecation.rails") do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_deprecation(event)
          rescue => e
            nil
          end
        end

        # --- Event handlers ---

        def handle_sql(event)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload
          return unless payload

          # Skip SCHEMA queries (e.g., "SCHEMA" name during migrations/introspection)
          return if payload[:name].to_s == "SCHEMA"

          sql = payload[:sql].to_s

          # Skip internal gem queries to avoid recursion
          return if sql.include?("rails_error_dashboard_")

          # Truncate SQL for storage
          message = sql.length > SQL_MESSAGE_MAX ? sql[0, SQL_MESSAGE_MAX] : sql
          duration = event.duration

          Services::BreadcrumbCollector.add("sql", message, duration_ms: duration)
        end

        def handle_controller(event)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload
          return unless payload

          controller = payload[:controller].to_s
          action = payload[:action].to_s
          message = "#{controller}##{action}"

          Services::BreadcrumbCollector.add("controller", message, duration_ms: event.duration)
        end

        def handle_cache(event, operation)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload
          return unless payload

          key = payload[:key].to_s
          message = "cache #{operation}: #{key}"

          metadata = nil
          if operation == "read" && !payload[:hit].nil?
            metadata = { hit: payload[:hit] }
          end

          Services::BreadcrumbCollector.add("cache", message, duration_ms: event.duration, metadata: metadata)
        end

        def handle_job(event)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload
          return unless payload

          job_class = payload[:job]&.class&.name || "UnknownJob"
          Services::BreadcrumbCollector.add("job", job_class, duration_ms: event.duration)
        end

        def handle_mailer(event)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload
          return unless payload

          mailer = payload[:mailer].to_s
          to = Array(payload[:to]).join(", ")
          message = "#{mailer} to: [#{to}]"

          Services::BreadcrumbCollector.add("mailer", message, duration_ms: event.duration)
        end

        def handle_deprecation(event)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload
          return unless payload

          message = payload[:message].to_s
          metadata = nil

          if payload[:callstack].is_a?(Array) && payload[:callstack].first
            metadata = { caller: payload[:callstack].first.to_s }
          end

          Services::BreadcrumbCollector.add("deprecation", message, metadata: metadata)
        end
      end
    end
  end
end
