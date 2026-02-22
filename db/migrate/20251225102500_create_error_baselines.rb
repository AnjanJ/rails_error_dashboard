# frozen_string_literal: true

class CreateErrorBaselines < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already created this table
    return if table_exists?(:rails_error_dashboard_error_baselines)

    create_table :rails_error_dashboard_error_baselines do |t|
      t.string :error_type, null: false
      t.string :platform, null: false
      t.string :baseline_type, null: false # hourly, daily, weekly
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false

      # Statistical metrics
      t.integer :count, null: false, default: 0
      t.float :mean
      t.float :std_dev
      t.float :percentile_95
      t.float :percentile_99
      t.integer :sample_size, null: false, default: 0

      t.timestamps
    end

    # Composite index for efficient baseline lookups
    add_index :rails_error_dashboard_error_baselines,
              [ :error_type, :platform, :baseline_type, :period_start ],
              name: 'index_error_baselines_on_type_platform_baseline_period'

    # Index for querying by error_type and platform
    add_index :rails_error_dashboard_error_baselines,
              [ :error_type, :platform ],
              name: 'index_error_baselines_on_error_type_and_platform'

    # Index for cleaning up old baselines
    add_index :rails_error_dashboard_error_baselines,
              :period_end,
              name: 'index_error_baselines_on_period_end'
  end
end
