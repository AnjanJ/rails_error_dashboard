# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Upsert buffered Rack::Attack event counts into the database.
    #
    # Receives a snapshot hash from RackAttackTracker and merges it into
    # hourly-bucketed rows. Uses find_or_initialize_by + increment for
    # cross-database compatibility (no raw SQL upsert).
    #
    # counts keys: "rule\x1Fmatch_type\x1Fdiscriminator\x1Fpath\x1Fhttp_method\x1Fuser_agent"
    #
    # http_method and user_agent are carried on the key but are NOT part of the
    # row's identity — see upsert_event.
    class FlushRackAttackEvents
      def self.call(counts:)
        new(counts: counts).call
      end

      def initialize(counts:)
        @counts = counts || {}
      end

      def call
        return if @counts.empty?

        period = Time.current.beginning_of_hour
        app_id = current_application_id

        @counts.each do |key, count|
          rule, match_type, discriminator, path, http_method, user_agent =
            Services::RackAttackTracker.parse_key(key)

          next if rule.blank? || match_type.blank?

          upsert_event(
            rule: rule,
            match_type: match_type,
            discriminator: discriminator,
            path: path,
            http_method: http_method,
            user_agent: user_agent,
            period: period,
            app_id: app_id,
            count: count
          )
        end
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushRackAttackEvents failed: #{e.class} - #{e.message}"
        )
      end

      private

      def upsert_event(rule:, match_type:, discriminator:, path:, http_method:, user_agent:,
                       period:, app_id:, count:)
        # nil and "" must map to the same row — the unique index treats them as
        # distinct in some adapters, so normalize blanks to nil consistently.
        record = RackAttackEvent.find_or_initialize_by(
          rule: rule,
          match_type: match_type,
          discriminator: discriminator.presence,
          path: path.presence,
          period_hour: period,
          application_id: app_id
        )

        # http_method and user_agent are deliberately NOT part of the upsert key
        # (the unique index is already at 2736 of MySQL's 3072 bytes), so they
        # are first-write-wins attributes of the bucket rather than identity.
        record.http_method = http_method.presence if record.http_method.blank?
        record.user_agent = user_agent.presence if record.user_agent.blank?
        record.event_count = (record.event_count || 0) + count
        record.last_seen_at = Time.current
        record.save!
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushRackAttackEvents.upsert_event failed for #{rule}: #{e.message}"
        )
      end

      def current_application_id
        app_name = RailsErrorDashboard.configuration.application_name
        return nil unless app_name.present?

        Application.find_by(name: app_name)&.id
      rescue => e
        nil
      end
    end
  end
end
