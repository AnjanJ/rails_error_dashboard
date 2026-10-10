# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: the host app's missing translation keys, most-missed first.
    #
    # Reads the missing_translations table (indexed SQL, no JSON parsing) for
    # rows last seen inside the window. One entry per (locale, key): the same
    # key missing in two locales is two rows, because fixing one locale file
    # does not fix the other.
    class MissingTranslationSummary
      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      # @return [Hash] entries: [{locale:, key:, source:, count:, first_seen:, last_seen:}],
      #   overflow_count: Integer, locales: [String]
      def call
        return empty unless MissingTranslation.table_exists?

        {
          entries: entries,
          overflow_count: overflow_count,
          locales: locales
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] MissingTranslationSummary query failed: #{e.class}: #{e.message}")
        empty
      end

      private

      def empty
        { entries: [], overflow_count: 0, locales: [] }
      end

      def base_query
        scope = MissingTranslation.seen_since(@start_date)
        scope = scope.for_application(@application_id) if @application_id.present?
        scope
      end

      # Merged in Ruby by (locale, key) rather than trusted to be unique: the
      # upsert index includes application_id, and a NULL there (no
      # application_name configured) lets two threads' first writes of the
      # same key both land, on every database. Two rows for one key would
      # read as two problems; summing them reads as one.
      def entries
        rows = base_query.real
          .pluck(:locale, :translation_key, :source, :miss_count, :first_seen_at, :last_seen_at)

        merged = {}
        rows.each do |locale, key, source, count, first_seen, last_seen|
          entry = merged[[ locale.to_s, key.to_s ]] ||= {
            locale: locale.to_s, key: key.to_s, source: nil, count: 0, first_seen: nil, last_seen: nil
          }
          entry[:count] += count.to_i
          entry[:source] ||= source.presence
          entry[:first_seen] = [ entry[:first_seen], first_seen ].compact.min
          entry[:last_seen] = [ entry[:last_seen], last_seen ].compact.max
        end

        merged.values.sort_by { |e| [ -e[:count], -(e[:last_seen]&.to_f || 0) ] }
      end

      # Misses the tracker could not attribute to a key because its buffer was
      # full. Kept out of the listing (they belong to no key) but reported so
      # the page never silently understates the total.
      def overflow_count
        base_query.overflow.sum(:miss_count).to_i
      rescue => e
        0
      end

      def locales
        base_query.real.distinct.pluck(:locale).map(&:to_s).sort
      rescue => e
        []
      end
    end
  end
end
