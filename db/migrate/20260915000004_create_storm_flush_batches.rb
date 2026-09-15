# frozen_string_literal: true

# Batch identity for storm count reconciliation, so a replayed batch is
# applied exactly once.
#
# FlushStormCounts applies counts additively:
#
#   UPDATE error_logs SET occurrence_count = occurrence_count + N
#
# which is not idempotent. Delivering the identical five-event snapshot twice
# persisted ten occurrences. The realistic replay path is the job's own
# retry: StormFlushJob raises when a batch reconciles nothing, and
# ApplicationJob retries it three times with the identical payload -- so a
# batch that partially applied and then failed was re-applied in full on the
# next attempt. A queue that redelivers does the same thing.
#
# This table is the ledger. A digest of the batch is inserted in the SAME
# transaction as the increments, so either both land or neither does. A
# replay hits the unique index, and the command reports the batch as already
# applied instead of counting it again.
#
# Small and self-expiring: at most one row per flush interval per process
# (~120/hour while a storm is actually running, none otherwise), pruned by
# RetentionCleanupJob alongside the rack-attack events.
class CreateStormFlushBatches < ActiveRecord::Migration[7.0]
  def change
    # Guard against a squashed schema migration having already created this
    # table -- without it, every later migration is silently cancelled.
    return if table_exists?(:rails_error_dashboard_storm_flush_batches)

    create_table :rails_error_dashboard_storm_flush_batches do |t|
      # SHA256 hex of the batch's identity parts. 64 chars, far inside
      # MySQL's 3072-byte utf8mb4 index limit (64 * 4 + 2 = 258 bytes).
      t.string :digest, null: false, limit: 64
      # What the batch carried, for operators reading the ledger directly.
      t.integer :entry_count, null: false, default: 0
      t.bigint :occurrences_applied, null: false, default: 0
      t.datetime :applied_at, null: false
      t.timestamps
    end

    add_index :rails_error_dashboard_storm_flush_batches, :digest,
              unique: true,
              name: "index_storm_flush_batches_on_digest"

    # Retention prunes on this column.
    add_index :rails_error_dashboard_storm_flush_batches, :applied_at,
              name: "index_storm_flush_batches_on_applied_at"
  end
end
