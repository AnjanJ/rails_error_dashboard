# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddEnhancedMetricsToErrorLogs < ActiveRecord::Migration[7.0]
  def up
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

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    %i[app_version git_sha priority_score].each do |column|
      remove_index :rails_error_dashboard_error_logs, column, if_exists: true
      remove_column :rails_error_dashboard_error_logs, column, if_exists: true
    end
  end
end
