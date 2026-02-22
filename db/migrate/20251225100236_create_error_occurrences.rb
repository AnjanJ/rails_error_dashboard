# frozen_string_literal: true

class CreateErrorOccurrences < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already created this table
    return if table_exists?(:rails_error_dashboard_error_occurrences)

    create_table :rails_error_dashboard_error_occurrences do |t|
      t.references :error_log, null: false, foreign_key: { to_table: :rails_error_dashboard_error_logs }
      t.datetime :occurred_at, null: false
      t.integer :user_id
      t.string :request_id
      t.string :session_id

      t.timestamps
    end

    # Index for finding co-occurring errors by time window
    add_index :rails_error_dashboard_error_occurrences, [ :occurred_at, :error_log_id ],
              name: 'index_error_occurrences_on_time_and_error'

    # Index for finding all occurrences of a specific error
    add_index :rails_error_dashboard_error_occurrences, :error_log_id,
              name: 'index_error_occurrences_on_error_log'

    # Index for finding errors by user
    add_index :rails_error_dashboard_error_occurrences, :user_id,
              name: 'index_error_occurrences_on_user'

    # Index for finding errors by request
    add_index :rails_error_dashboard_error_occurrences, :request_id,
              name: 'index_error_occurrences_on_request'
  end
end
