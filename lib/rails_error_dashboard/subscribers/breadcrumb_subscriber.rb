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

          @subscriptions
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

          Services::BreadcrumbCollector.add("cache", message, duration_ms: event.duration)
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
      end
    end
  end
end
