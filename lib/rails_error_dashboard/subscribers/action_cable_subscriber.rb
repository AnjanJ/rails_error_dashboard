# frozen_string_literal: true

module RailsErrorDashboard
  module Subscribers
    # Registers ActiveSupport::Notifications subscribers for ActionCable events.
    #
    # ActionCable emits:
    # - perform_action.action_cable          — channel action executed
    # - transmit.action_cable                — data transmitted to subscriber
    # - transmit_subscription_confirmation.action_cable — subscription confirmed
    # - transmit_subscription_rejection.action_cable    — subscription rejected
    #
    # Each event is captured as a breadcrumb with category "action_cable",
    # allowing correlation between WebSocket events and error spikes.
    #
    # SAFETY RULES (HOST_APP_SAFETY.md):
    # - Every subscriber wrapped in rescue => e; nil
    # - Never raise from subscriber callbacks
    # - Skip if buffer is nil (not in a request context)
    class ActionCableSubscriber
      EVENTS = %w[
        perform_action.action_cable
        transmit.action_cable
        transmit_subscription_confirmation.action_cable
        transmit_subscription_rejection.action_cable
      ].freeze

      # Event subscriptions managed by this class
      @subscriptions = []

      class << self
        attr_reader :subscriptions

        # Register all ActionCable event subscribers
        # @return [Array] Array of subscription objects
        def subscribe!
          @subscriptions = []

          EVENTS.each do |event_name|
            @subscriptions << subscribe_event(event_name)
          end

          @subscriptions
        end

        # Remove all ActionCable subscribers
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
            handle_action_cable(event, event_name)
          rescue => e
            nil
          end
        end

        def handle_action_cable(event, event_name)
          return unless Services::BreadcrumbCollector.current_buffer

          payload = event.payload || {}
          channel = payload[:channel_class] || payload[:channel] || "Unknown"
          channel = channel.to_s

          event_type = event_name.split(".").first # "perform_action", "transmit", etc.
          action = payload[:action].to_s

          message = build_message(event_type, channel, action)

          metadata = {
            channel: channel,
            event_type: event_type
          }
          metadata[:action] = action if action.present?

          duration_ms = event.duration if event.respond_to?(:duration)

          Services::BreadcrumbCollector.add("action_cable", message, duration_ms: duration_ms, metadata: metadata)
        end

        def build_message(event_type, channel, action)
          case event_type
          when "perform_action"
            action.present? ? "perform: #{channel}##{action}" : "perform: #{channel}"
          when "transmit"
            "transmit: #{channel}"
          when "transmit_subscription_confirmation"
            "subscribed: #{channel}"
          when "transmit_subscription_rejection"
            "rejected: #{channel}"
          else
            "#{event_type}: #{channel}"
          end
        end
      end
    end
  end
end
