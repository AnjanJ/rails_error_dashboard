# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: fill in `environment` on error logs captured before the column
    # existed, using the rails_env recorded in environment_info at capture time.
    #
    # Opt-in (rails_error_dashboard:backfill_environments). Live errors do not
    # need it — FindOrIncrementError adopts a NULL row on its next occurrence —
    # but history that never recurs would otherwise stay unbadged and
    # unfilterable forever.
    #
    # Runs in batches, one UPDATE per row: the value is inside a JSON text
    # column, so it has to be parsed in Ruby and no portable single UPDATE can
    # do it across PostgreSQL, MySQL and SQLite.
    class BackfillEnvironments
      BATCH_SIZE = 500
      COLUMN_LIMIT = 64

      def self.call(batch_size: BATCH_SIZE)
        new(batch_size: batch_size).call
      end

      def initialize(batch_size: BATCH_SIZE)
        @batch_size = batch_size
      end

      # @return [Integer] rows updated
      def call
        return 0 unless ErrorLog.column_names.include?("environment")

        updated = 0
        ErrorLog.where(environment: nil).where.not(environment_info: nil)
                .in_batches(of: @batch_size) do |batch|
          batch.pluck(:id, :environment_info).each do |id, raw|
            env = rails_env_from(raw)
            next if env.nil?

            updated += ErrorLog.where(id: id, environment: nil).update_all(environment: env)
          end
        end
        updated
      end

      private

      def rails_env_from(raw)
        parsed = JSON.parse(raw.to_s)
        return nil unless parsed.is_a?(Hash)

        value = parsed["rails_env"].to_s.strip
        value.empty? ? nil : value[0, COLUMN_LIMIT]
      rescue JSON::ParserError
        nil
      end
    end
  end
end
