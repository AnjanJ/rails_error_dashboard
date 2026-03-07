# frozen_string_literal: true

module RailsErrorDashboard
  module Subscribers
    # Registers ActiveSupport::Notifications subscribers for Rack::Attack events.
    #
    # Rack Attack (v5.0+) emits:
    # - throttle.rack_attack   — rate-limited requests
    # - blocklist.rack_attack  — blocked requests
    # - track.rack_attack      — tracked (observed) requests
    #
    # Each event is captured as a breadcrumb with category "rack_attack",
    # allowing correlation between rate-limit events and error spikes.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Every subscriber wrapped in rescue => e; nil
    # - Never raise from subscriber callbacks
    # - Skip if buffer is nil (not in a request context)
    class RackAttackSubscriber
      EVENTS = %w[
        throttle.rack_attack
        blocklist.rack_attack
        track.rack_attack
      ].freeze

      # Event subscriptions managed by this class
      @subscriptions = []

      class << self
        attr_reader :subscriptions

        # Register all Rack Attack event subscribers
        # @return [Array] Array of subscription objects
        def subscribe!
          @subscriptions = []

          EVENTS.each do |event_name|
            @subscriptions << subscribe_event(event_name)
          end

          @subscriptions
        end

        # Remove all Rack Attack subscribers
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
            handle_rack_attack(event, event_name)
          rescue => e
            nil
          end
        end

        def handle_rack_attack(event, event_name)
          return unless Services::BreadcrumbCollector.current_buffer

          request = event.payload[:request]
          return unless request

          env = request.respond_to?(:env) ? request.env : {}

          match_type = event_name.split(".").first # "throttle", "blocklist", "track"
          rule = env["rack.attack.matched"].to_s
          discriminator = env["rack.attack.match_discriminator"].to_s
          path = request.respond_to?(:path) ? request.path.to_s : ""
          method = request.respond_to?(:request_method) ? request.request_method.to_s : ""

          message = "#{match_type}: #{rule} (#{discriminator}) #{method} #{path}"

          metadata = {
            rule: rule,
            type: match_type,
            discriminator: discriminator,
            path: path,
            method: method
          }

          Services::BreadcrumbCollector.add("rack_attack", message, metadata: metadata)
        end
      end
    end
  end
end
