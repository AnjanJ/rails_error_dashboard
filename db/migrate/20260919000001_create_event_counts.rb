# frozen_string_literal: true

# Time buckets for storm-shed event volume.
#
# Every time-window figure on the dashboard ("errors today", the daily trend,
# the hourly chart, the error rate) used to filter error_logs by occurred_at
# and then SUM(occurrence_count). occurred_at is FIRST-SEEN and is never
# rewritten on recurrence, so that sum reports the lifetime volume of the
# groups born inside the window -- not the events that happened in it. An
# error first seen at 23:59 and recurring at 00:01 reported "0 errors today"
# and put both events on yesterday.
#
# The obvious fix -- count error_occurrences rows in the window -- is wrong on
# its own. Storm protection deliberately writes NO occurrence row while
# shedding: it folds N events into occurrence_count and nothing else. Counting
# occurrence rows would therefore erase storm volume from every time window,
# which is exactly when the numbers matter most.
#
# So shed volume needs its own timestamp, and this is it: one row per
# (error group, hour), holding how many shed events landed in that hour.
# Window volume is then
#
#   occurrence rows in the window + shed bucket counts in the window
#
# which is correct for both ordinary and shed events.
#
# Small by construction: a row is written only while a storm is actually
# shedding, at most one per group per hour, and RetentionCleanupJob prunes it
# on bucket_at alongside the other aggregate tables.
class CreateEventCounts < ActiveRecord::Migration[7.0]
  def change
    # Guard against a squashed schema migration having already created this
    # table -- without it, every later migration is silently cancelled.
    return if table_exists?(:rails_error_dashboard_event_counts)

    create_table :rails_error_dashboard_event_counts do |t|
      t.bigint :error_log_id, null: false
      # Truncated to the hour, in UTC. The hour is the finest bucket any
      # dashboard view needs (the hourly chart) and keeps the row count bounded
      # even through a long storm.
      t.datetime :bucket_at, null: false
      t.bigint :count, null: false, default: 0
      t.timestamps
    end

    # The upsert target: one bucket per group per hour. Named explicitly --
    # an auto-generated name here would exceed PostgreSQL's 63-character limit
    # and fail during the HOST app's deploy (see mailboxer#480).
    add_index :rails_error_dashboard_event_counts, [ :error_log_id, :bucket_at ],
              unique: true,
              name: "index_red_event_counts_on_group_and_bucket"

    # Window queries scan by time; retention prunes on the same column.
    add_index :rails_error_dashboard_event_counts, :bucket_at,
              name: "index_red_event_counts_on_bucket_at"
  end
end
