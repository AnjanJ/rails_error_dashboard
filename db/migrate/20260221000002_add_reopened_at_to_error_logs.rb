# frozen_string_literal: true

class AddReopenedAtToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_error_dashboard_error_logs, :reopened_at, :datetime
  end
end
