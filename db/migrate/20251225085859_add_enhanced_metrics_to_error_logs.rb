class AddEnhancedMetricsToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :app_version)

    add_column :rails_error_dashboard_error_logs, :app_version, :string
    add_column :rails_error_dashboard_error_logs, :git_sha, :string
    add_column :rails_error_dashboard_error_logs, :priority_score, :integer

    # Indexes for enhanced metrics
    add_index :rails_error_dashboard_error_logs, :app_version
    add_index :rails_error_dashboard_error_logs, :git_sha
    add_index :rails_error_dashboard_error_logs, :priority_score
  end
end
