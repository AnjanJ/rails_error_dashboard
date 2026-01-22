# frozen_string_literal: true

class CreateRailsErrorDashboardErrorLogs < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already ran (checks for column added in later migration)
    # If application_id column exists, the squashed migration created the table
    return if table_exists?(:rails_error_dashboard_error_logs) &&
              column_exists?(:rails_error_dashboard_error_logs, :application_id)

    create_table :rails_error_dashboard_error_logs do |t|
      # Error details
      t.string :error_type, null: false
      t.text :message, null: false
      t.text :backtrace

      # Context
      t.integer :user_id
      t.text :request_url
      t.text :request_params
      t.text :user_agent
      t.string :ip_address
      t.string :environment, null: false
      t.string :platform

      # Resolution tracking
      t.boolean :resolved, default: false, null: false
      t.text :resolution_comment
      t.string :resolution_reference
      t.string :resolved_by_name
      t.datetime :resolved_at

      # Timestamps
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    # Indexes for performance
    add_index :rails_error_dashboard_error_logs, :user_id
    add_index :rails_error_dashboard_error_logs, :error_type
    add_index :rails_error_dashboard_error_logs, :environment
    add_index :rails_error_dashboard_error_logs, :resolved
    add_index :rails_error_dashboard_error_logs, :occurred_at
    add_index :rails_error_dashboard_error_logs, :platform
  end
end
