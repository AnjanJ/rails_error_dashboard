# frozen_string_literal: true

module RailsErrorDashboard
  module Subscribers
    # Registers ActiveSupport::Notifications subscribers for ActiveStorage events.
    #
    # ActiveStorage emits:
    # - service_upload.active_storage          — file uploaded to storage service
    # - service_download.active_storage        — file downloaded from storage service
    # - service_streaming_download.active_storage — streaming download
    # - service_delete.active_storage          — file deleted from storage service
    # - service_delete_prefixed.active_storage — batch delete by prefix
    # - service_exist.active_storage           — existence check
    #
    # Each event is captured as a breadcrumb with category "active_storage",
    # allowing correlation between storage operations and error spikes.
    #
    # SAFETY RULES (.claude/skills/host-app-safety/SKILL.md):
    # - Every subscriber wrapped in rescue => e; nil
    # - Never raise from subscriber callbacks
    # - Skip if buffer is nil (not in a request context)
    class ActiveStorageSubscriber
      EVENTS = %w[
        service_upload.active_storage
        service_download.active_storage
        service_streaming_download.active_storage
        service_delete.active_storage
        service_delete_prefixed.active_storage
        service_exist.active_storage
      ].freeze

      # Event subscriptions managed by this class
      @subscriptions = []

      class << self
        attr_reader :subscriptions

        # Register all ActiveStorage event subscribers
        # @return [Array] Array of subscription objects
        def subscribe!
          @subscriptions = []

          EVENTS.each do |event_name|
            @subscriptions << subscribe_event(event_name)
          end

          @subscriptions
        end

        # Remove all ActiveStorage subscribers
        def unsubscribe!
          @subscriptions.each do |sub|
            ActiveSupport::Notifications.unsubscribe(sub) if sub
          rescue => e
            nil
          end
          @subscriptions = []
        end

        private

        def subscribe_event(event_name)
          ActiveSupport::Notifications.subscribe(event_name) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            handle_active_storage(event, event_name)
          rescue => e
            nil
          end
        end

        def handle_active_storage(event, event_name)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload || {}
          service = payload[:service].to_s.presence || "Unknown"
          operation = event_name.split(".").first.sub("service_", "")
          key = (payload[:key] || payload[:prefix]).to_s

          message = build_message(operation, service, key)

          metadata = {
            service: service,
            operation: operation
          }
          metadata[:key] = key.truncate(100) if key.present?

          duration_ms = event.duration if event.respond_to?(:duration)

          Services::BreadcrumbCollector.add("active_storage", message, duration_ms: duration_ms, metadata: metadata)
        end

        def build_message(operation, service, key)
          short_key = key.present? ? key.truncate(40) : nil
          case operation
          when "upload"
            short_key ? "upload #{short_key} (#{service})" : "upload (#{service})"
          when "download", "streaming_download"
            short_key ? "download #{short_key} (#{service})" : "download (#{service})"
          when "delete"
            short_key ? "delete #{short_key} (#{service})" : "delete (#{service})"
          when "delete_prefixed"
            short_key ? "delete_prefixed #{short_key} (#{service})" : "delete_prefixed (#{service})"
          when "exist"
            short_key ? "exist? #{short_key} (#{service})" : "exist? (#{service})"
          else
            "#{operation} (#{service})"
          end
        end
      end
    end
  end
end
