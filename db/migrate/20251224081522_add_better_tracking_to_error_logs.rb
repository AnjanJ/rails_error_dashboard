class AddBetterTrackingToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :error_hash)

    add_column :rails_error_dashboard_error_logs, :error_hash, :string
    add_column :rails_error_dashboard_error_logs, :first_seen_at, :datetime
    add_column :rails_error_dashboard_error_logs, :last_seen_at, :datetime
    add_column :rails_error_dashboard_error_logs, :occurrence_count, :integer, default: 1, null: false

    add_index :rails_error_dashboard_error_logs, :error_hash
    add_index :rails_error_dashboard_error_logs, :first_seen_at
    add_index :rails_error_dashboard_error_logs, :last_seen_at
    add_index :rails_error_dashboard_error_logs, :occurrence_count
  end
end
