# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: give resolved errors that have no resolved_at a best-known one
    #
    # Errors resolved through the status workflow before 0.13.0 were marked
    # resolved without a resolved_at, so MTTR never counted them. The moment of
    # resolution was not recorded anywhere, but it was the row's last write
    # unless something touched it afterwards, so updated_at is the closest
    # available value.
    #
    # Behind `rake error_dashboard:backfill_resolved_at`. Idempotent: it only
    # selects rows whose resolved_at is still NULL.
    #
    # @example
    #   BackfillResolvedAt.call # => { updated: 42 }
    class BackfillResolvedAt
      BATCH_SIZE = 1000

      def self.call(batch_size: BATCH_SIZE)
        new(batch_size: batch_size).call
      end

      def initialize(batch_size: BATCH_SIZE)
        @batch_size = batch_size
      end

      def call
        updated = 0

        ErrorLog.where(resolved: true, resolved_at: nil).in_batches(of: @batch_size) do |batch|
          # SQL column reference, not a Ruby value: each row gets its own
          # updated_at. update_all leaves updated_at itself alone.
          updated += batch.update_all("resolved_at = updated_at")
        end

        { updated: updated }
      end
    end
  end
end
