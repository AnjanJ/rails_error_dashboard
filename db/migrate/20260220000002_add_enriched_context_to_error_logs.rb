# frozen_string_literal: true

class AddEnrichedContextToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_error_dashboard_error_logs, :http_method, :string, limit: 10
    add_column :rails_error_dashboard_error_logs, :hostname, :string, limit: 255
    add_column :rails_error_dashboard_error_logs, :content_type, :string, limit: 100
    add_column :rails_error_dashboard_error_logs, :request_duration_ms, :integer
  end
end
