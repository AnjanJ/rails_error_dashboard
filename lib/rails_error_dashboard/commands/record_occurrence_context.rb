# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Keeps one occurrence's moment-of-failure context, then trims the error's
    # stored contexts to the newest config.occurrence_context_limit.
    #
    # The values are the JSON strings LogError has just written to the error
    # row (breadcrumbs, system health, local and instance variables), so an
    # occurrence holds exactly what the row would, filtered the same way. A
    # capture with none of them (a storm-protection :lite capture, or every
    # feature off) stores nothing.
    #
    # Runs inside the capture: it never raises.
    class RecordOccurrenceContext
      PIECES = %i[breadcrumbs system_health local_variables instance_variables].freeze

      # @param occurrence [ErrorOccurrence] the occurrence just created
      # @param attributes [Hash] the attributes LogError wrote to the error row
      def self.call(occurrence, attributes)
        new(occurrence, attributes).call
      end

      def initialize(occurrence, attributes)
        @occurrence = occurrence
        @attributes = attributes
      end

      def call
        limit = RailsErrorDashboard.configuration.occurrence_context_limit.to_i
        return if limit <= 0

        values = PIECES.index_with { |piece| @attributes[piece].presence }.compact
        return if values.empty?

        # An app that updated the gem but has not migrated yet
        return unless ErrorOccurrenceContext.table_exists?

        ErrorOccurrenceContext.create!(
          values.merge(error_occurrence_id: @occurrence.id, error_log_id: @occurrence.error_log_id, created_at: Time.current)
        )
        trim(limit)
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Failed to record occurrence context: #{e.class}: #{e.message}"
        )
        nil
      end

      private

      # Everything past the newest `limit`, normally the one the insert pushed out
      def trim(limit)
        stale = ErrorOccurrenceContext.where(error_log_id: @occurrence.error_log_id)
          .order(id: :desc).offset(limit).pluck(:id)
        ErrorOccurrenceContext.where(id: stale).delete_all if stale.any?
      end
    end
  end
end
