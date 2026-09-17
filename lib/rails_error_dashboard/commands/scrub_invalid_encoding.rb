# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: repair rows that were stored with invalid bytes
    #
    # New captures are scrubbed on the way in (Services::EncodingSanitizer), but
    # that does nothing for rows already in the table. SQLite and MySQL accept
    # invalid UTF-8 and NUL bytes, and a row holding them makes the pages that
    # render it answer 500. PostgreSQL rejects such rows at INSERT, so there is
    # normally nothing to repair there; the scan is harmless.
    #
    # Behind `rake error_dashboard:scrub_invalid_encoding`. Safe to re-run: a
    # second pass finds nothing to repair.
    #
    # @example
    #   ScrubInvalidEncoding.call # => { scanned: 1200, repaired: 3, unreadable: [] }
    class ScrubInvalidEncoding
      BATCH_SIZE = 500

      MODEL_NAMES = %w[ErrorLog ErrorOccurrence].freeze

      def self.call(batch_size: BATCH_SIZE)
        new(batch_size: batch_size).call
      end

      def initialize(batch_size: BATCH_SIZE)
        @batch_size = batch_size
        @scanned = 0
        @repaired = 0
        @unreadable = []
      end

      # @return [Hash] { scanned:, repaired:, unreadable: [ "ErrorLog#12", ... ] }
      def call
        models.each { |model| scrub_model(model) }

        { scanned: @scanned, repaired: @repaired, unreadable: @unreadable }
      end

      private

      def models
        MODEL_NAMES.filter_map do |name|
          model = RailsErrorDashboard.const_get(name)
          model if model.table_exists?
        rescue => e
          RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] ScrubInvalidEncoding skipped #{name}: #{e.class}")
          nil
        end
      end

      def scrub_model(model)
        columns = model.columns.select { |column| %i[string text].include?(column.type) }.map(&:name)
        return if columns.empty?

        model.in_batches(of: @batch_size) do |batch|
          ids = batch.pluck(model.primary_key)
          load_rows(model, ids).each { |row| scrub_row(row, columns) }
        end
      end

      # One query per batch; if that batch cannot be materialised at all, fall
      # back to row-by-row so a single unreadable row is reported by id instead
      # of hiding the 499 readable ones around it.
      def load_rows(model, ids)
        model.where(model.primary_key => ids).to_a
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] ScrubInvalidEncoding batch read failed: #{e.class}")
        ids.filter_map do |id|
          model.find(id)
        rescue => row_error
          @unreadable << "#{model.name.demodulize}##{id} (#{row_error.class})"
          nil
        end
      end

      def scrub_row(row, columns)
        @scanned += 1

        changes = columns.each_with_object({}) do |column, fixed|
          value = row.read_attribute(column)
          next unless value.is_a?(String)

          clean = Services::EncodingSanitizer.scrub(value)
          fixed[column] = clean unless clean.equal?(value) || clean == value
        end
        # The model scrubs invalid strings as it loads a row, so by now they
        # read as clean. It remembers which ones it had to repair.
        row.invalid_encoding_attributes.each do |column|
          changes[column] = row.read_attribute(column) if columns.include?(column)
        end
        return if changes.empty?

        # update_columns: no callbacks, no validations, no updated_at bump. This
        # is a byte-level repair, not an edit.
        row.update_columns(changes)
        @repaired += 1
      rescue => e
        @unreadable << "#{row.class.name.demodulize}##{row.id} (#{e.class})"
      end
    end
  end
end
