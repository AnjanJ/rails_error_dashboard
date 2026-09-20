# frozen_string_literal: true

# Records that a storm episode lost its per-bucket TIMING evidence.
#
# When the rollup table is permanently unavailable (never migrated, or an
# adapter that refuses the statement), FlushStormCounts deliberately degrades:
# it keeps the authoritative lifetime occurrence_count and skips the bucket.
# That is the right trade -- losing a time bucket beats losing a count -- but
# it leaves every time-window figure for that episode resting on the group's
# own occurred_at rather than on per-event evidence.
#
# The flag was returned in the flush result and then dropped on the floor: no
# caller persisted it, no query read it, and nothing on the dashboard said so.
# A replay lost it entirely. Persisting it on the episode is what lets the
# Overview report an incomplete dimension instead of presenting a figure of
# unknown completeness as fact -- exactly as affected_users_incomplete already
# does for storm-shed occurrence rows.
class AddBucketsIncompleteToStormEvents < ActiveRecord::Migration[7.0]
  def change
    return unless table_exists?(:rails_error_dashboard_storm_events)
    return if column_exists?(:rails_error_dashboard_storm_events, :buckets_incomplete)

    add_column :rails_error_dashboard_storm_events, :buckets_incomplete, :boolean, default: false
  end
end
