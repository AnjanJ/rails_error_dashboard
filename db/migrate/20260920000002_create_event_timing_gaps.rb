# frozen_string_literal: true

# One row per interval whose per-event TIMING evidence was lost.
#
# When the rollup table is permanently unavailable, FlushStormCounts keeps the
# authoritative lifetime occurrence_count and skips the bucket. The counts stay
# exact; only their placement in time becomes approximate. The dashboard has to
# say so, or it presents a figure of unknown completeness as fact.
#
# Three earlier attempts to carry that fact failed, each for a structural
# reason, and this table exists to fix all three at once:
#
#   1. A boolean in the command's RETURN HASH. A background job's return value
#      never reaches the dashboard.
#   2. A flag on the storm EPISODE. The episode is OPTIONAL -- the gate can
#      shed events with its breaker closed and pass episode: nil -- so the
#      warning silently vanished exactly when no episode existed.
#   3. Written by upsert_storm_event, which runs AFTER the counts transaction
#      commits and rescues its own failures. A transient save failure lost the
#      marker while the batch ledger recorded the batch as applied, so the
#      replay was suppressed and the gap was never recorded.
#
# So: its own table, written INSIDE the same transaction as the counts (either
# both land or neither does), keyed by the interval it describes rather than by
# an episode that may not exist.
#
# Bounded by construction: one row per (application, bucket) per degraded
# flush, and only while the rollup is actually unusable -- which is a
# misconfiguration, not a steady state. Retention prunes it by covered_until.
class CreateEventTimingGaps < ActiveRecord::Migration[7.0]
  def change
    return if table_exists?(:rails_error_dashboard_event_timing_gaps)

    create_table :rails_error_dashboard_event_timing_gaps do |t|
      # Nullable: a gap can predate application scoping, and a NULL here means
      # "applies to every application" rather than "unknown".
      t.bigint :application_id
      # The interval whose timing is unreliable. covered_from is the earliest
      # event in the degraded flush, covered_until the latest.
      t.datetime :covered_from, null: false
      t.datetime :covered_until, null: false
      # How many events lost their timestamps, so the UI can say how much of
      # the window is affected rather than only that something is.
      t.bigint :events_affected, null: false, default: 0
      t.timestamps
    end

    # The read is "does any gap overlap the window I am displaying", which
    # scans on covered_until. Named explicitly -- an auto-generated name here
    # would exceed PostgreSQL's 63-character limit and fail during the HOST
    # app's deploy (see mailboxer#480).
    add_index :rails_error_dashboard_event_timing_gaps, :covered_until,
              name: "index_red_timing_gaps_on_covered_until"
  end
end
