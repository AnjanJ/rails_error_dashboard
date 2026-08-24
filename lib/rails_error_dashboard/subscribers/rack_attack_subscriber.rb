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
          request = event.payload[:request]
          return unless request

          env = request.respond_to?(:env) ? request.env : {}

          match_type = event_name.split(".").first # "throttle", "blocklist", "track"
          rule = env["rack.attack.matched"].to_s
          discriminator = resolve_discriminator(env, request)
          path = request.respond_to?(:path) ? request.path.to_s : ""
          method = request.respond_to?(:request_method) ? request.request_method.to_s : ""

          # Persist independently of error capture. A throttled request returns
          # HTTP 429 and raises nothing, so it would otherwise never reach the
          # database — breadcrumbs are only harvested by LogError (issue #143).
          Services::RackAttackTracker.record(
            rule: rule,
            match_type: match_type,
            discriminator: discriminator,
            path: path,
            http_method: method
          )

          # Also record a breadcrumb so the event still shows up in the activity
          # trail on the error detail page when an error DOES occur in the same
          # request. Requires an active request-scoped buffer.
          return unless Services::BreadcrumbCollector.current_buffer

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

        # Resolve the discriminator, falling back to the client IP.
        #
        # WHY (issue #170): a `track` rule declared without :limit/:period is a
        # Rack::Attack::Check, and Check#matched_by? sets only "rack.attack.matched"
        # and "rack.attack.match_type" — never "rack.attack.match_discriminator".
        # Only Throttle#annotate_request_with_matched_data sets that key. The value
        # the rule's block returns (typically `req.ip`) is used purely as a truthy
        # match test and then discarded upstream.
        #
        # Without this fallback every track row stores a blank discriminator, so
        # RackAttackSummary reports "Unique IPs: 0" for a rule that plainly matched
        # real clients. We use request.ip rather than re-invoking the rule's block:
        # the block is arbitrary host code that may have side effects or return a
        # non-IP value, and re-running it from a notification subscriber would
        # execute it a second time per request.
        def resolve_discriminator(env, request)
          explicit = env["rack.attack.match_discriminator"].to_s
          return explicit unless explicit.empty?

          # request.ip parses X-Forwarded-For and can raise on malformed input.
          request.respond_to?(:ip) ? request.ip.to_s : ""
        rescue => e
          ""
        end
      end
    end
  end
end
