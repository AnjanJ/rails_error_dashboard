# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: upsert a snapshot of buffered missing-translation counts.
    #
    # Receives { "locale\x1Fkey" => [count, source] } from
    # MissingTranslationTracker and adds each count to its (locale, key,
    # application) row, creating the row on first sight. find_or_initialize_by
    # + save! rather than a raw upsert, for cross-database compatibility; a
    # concurrent first insert of the same key is retried once as a read.
    #
    # Runs off the request path (executor to_complete, at_exit). Never raises:
    # a failed row is logged at debug and the rest of the snapshot still lands.
    class FlushMissingTranslations
      def self.call(counts:)
        new(counts: counts).call
      end

      def initialize(counts:)
        @counts = counts || {}
      end

      def call
        return if @counts.empty?
        return unless MissingTranslation.table_exists?

        now = Time.current
        app_id = current_application_id

        @counts.each do |buffer_key, (count, source)|
          # A key can be built from user input, so invalid bytes are possible.
          locale, translation_key = Services::MissingTranslationTracker.parse_key(
            Services::EncodingSanitizer.scrub(buffer_key.to_s)
          )
          next if locale.blank? || translation_key.blank? || count.to_i <= 0

          upsert(locale: locale, translation_key: translation_key,
                 source: source, count: count.to_i, app_id: app_id, now: now)
        end
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushMissingTranslations failed: #{e.class} - #{e.message}"
        )
      end

      private

      def upsert(locale:, translation_key:, source:, count:, app_id:, now:, retried: false)
        record = MissingTranslation.find_or_initialize_by(
          locale: locale,
          translation_key: translation_key,
          application_id: app_id
        )

        record.first_seen_at ||= now
        record.last_seen_at = now
        record.miss_count = (record.miss_count || 0) + count
        # First-write-wins: the first call site seen is the one worth showing,
        # and overwriting it on every flush would make the column flicker
        # between callers of the same key.
        record.source = Services::EncodingSanitizer.scrub(source.to_s).presence if record.source.blank?
        record.save!
      rescue ActiveRecord::RecordNotUnique
        # Another thread created the row between our read and our insert.
        # Once more as an update; a second collision is not worth a loop.
        raise if retried

        upsert(locale: locale, translation_key: translation_key, source: source,
               count: count, app_id: app_id, now: now, retried: true)
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushMissingTranslations.upsert failed for #{locale}.#{translation_key}: #{e.class} - #{e.message}"
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
