# frozen_string_literal: true

class AddEnvironmentInfoToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_error_dashboard_error_logs, :environment_info, :text
  end
end
