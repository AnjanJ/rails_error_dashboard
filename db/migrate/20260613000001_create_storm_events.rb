# frozen_string_literal: true

# Storm protection honesty layer: one row per storm episode, powering the
# dashboard banner ("storm detected, counts recorded, detail sampled") and
# the storm history page. Small table — a few rows per incident.
class CreateStormEvents < ActiveRecord::Migration[7.0]
  def change
    return if table_exists?(:rails_error_dashboard_storm_events)

    create_table :rails_error_dashboard_storm_events do |t|
      t.datetime :started_at, null: false
      t.datetime :ended_at                    # NULL while the storm is active
      t.integer :peak_rate_per_minute, default: 0
      t.boolean :reached_open, default: false # true if count-only mode engaged
      t.bigint :events_total, default: 0      # count-only total = counted_only + overflow (excludes :lite/:full rows)
      t.bigint :events_counted_only, default: 0 # counted in memory, no rows
      t.bigint :events_overflow, default: 0   # beyond the bounded map — exact total, anonymous identity
      t.integer :fingerprints_affected, default: 0
      t.text :top_fingerprints                # JSON: top 5 by count [{class, message, count}]
      t.timestamps
    end

    add_index :rails_error_dashboard_storm_events, :ended_at,
              name: "index_red_storm_events_on_ended_at"
    add_index :rails_error_dashboard_storm_events, :started_at,
              name: "index_red_storm_events_on_started_at"
  end
end
