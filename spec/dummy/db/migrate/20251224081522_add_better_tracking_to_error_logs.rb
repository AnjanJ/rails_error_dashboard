class AddBetterTrackingToErrorLogs < ActiveRecord::Migration[8.1]
  def change
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
