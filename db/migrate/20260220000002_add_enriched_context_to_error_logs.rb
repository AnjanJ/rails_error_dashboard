# frozen_string_literal: true

# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddEnrichedContextToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:rails_error_dashboard_error_logs, :http_method)
      add_column :rails_error_dashboard_error_logs, :http_method, :string, limit: 10
      add_column :rails_error_dashboard_error_logs, :hostname, :string, limit: 255
      add_column :rails_error_dashboard_error_logs, :content_type, :string, limit: 100
      add_column :rails_error_dashboard_error_logs, :request_duration_ms, :integer
    end
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    remove_column :rails_error_dashboard_error_logs, :http_method if column_exists?(:rails_error_dashboard_error_logs, :http_method)
    remove_column :rails_error_dashboard_error_logs, :hostname if column_exists?(:rails_error_dashboard_error_logs, :hostname)
    remove_column :rails_error_dashboard_error_logs, :content_type if column_exists?(:rails_error_dashboard_error_logs, :content_type)
    remove_column :rails_error_dashboard_error_logs, :request_duration_ms if column_exists?(:rails_error_dashboard_error_logs, :request_duration_ms)
  end
end
