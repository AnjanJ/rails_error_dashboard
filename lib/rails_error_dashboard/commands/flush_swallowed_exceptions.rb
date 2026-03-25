# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Upsert swallowed exception raise/rescue counts into the database.
    #
    # Receives snapshot hashes from SwallowedExceptionTracker and merges them
    # into hourly-bucketed rows. Uses find_or_initialize_by + increment for
    # cross-database compatibility (no raw SQL upsert).
    #
    # raise_counts keys: "ClassName|path:line"
    # rescue_counts keys: "ClassName|raise_path:line->rescue_path:line"
    class FlushSwallowedExceptions
      def self.call(raise_counts:, rescue_counts:)
        new(raise_counts: raise_counts, rescue_counts: rescue_counts).call
      end

      def initialize(raise_counts:, rescue_counts:)
        @raise_counts = raise_counts
        @rescue_counts = rescue_counts
      end

      def call
        period = Time.current.beginning_of_hour
        app_id = current_application_id

        # Process raise counts
        @raise_counts.each do |key, count|
          class_name, location = key.split("|", 2)
          next if class_name.blank? || location.blank?

          upsert_raise(class_name, location, period, app_id, count)
        end

        # Process rescue counts
        @rescue_counts.each do |key, count|
          class_name, locations = key.split("|", 2)
          next if class_name.blank? || locations.blank?

          raise_loc, rescue_loc = locations.split("->", 2)
          next if raise_loc.blank?

          upsert_rescue(class_name, raise_loc, rescue_loc, period, app_id, count)
        end
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushSwallowedExceptions failed: #{e.class} - #{e.message}"
        )
      end

      private

      def upsert_raise(class_name, location, period, app_id, count)
        record = SwallowedException.find_or_initialize_by(
          exception_class: truncate(class_name, 250),
          raise_location: truncate(location, 250),
          rescue_location: nil,
          period_hour: period,
          application_id: app_id
        )

        record.raise_count = (record.raise_count || 0) + count
        record.last_seen_at = Time.current
        record.save!
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushSwallowedExceptions.upsert_raise failed for #{class_name}: #{e.message}"
        )
      end

      def upsert_rescue(class_name, raise_loc, rescue_loc, period, app_id, count)
        record = SwallowedException.find_or_initialize_by(
          exception_class: truncate(class_name, 250),
          raise_location: truncate(raise_loc, 250),
          rescue_location: rescue_loc.present? ? truncate(rescue_loc, 250) : nil,
          period_hour: period,
          application_id: app_id
        )

        record.rescue_count = (record.rescue_count || 0) + count
        record.last_seen_at = Time.current
        record.save!
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] FlushSwallowedExceptions.upsert_rescue failed for #{class_name}: #{e.message}"
        )
      end

      def current_application_id
        app_name = RailsErrorDashboard.configuration.application_name
        return nil unless app_name.present?

        Application.find_by(name: app_name)&.id
      rescue => e
        nil
      end

      def truncate(str, max)
        str.to_s.truncate(max, omission: "")
      end
    end
  end
end
