# frozen_string_literal: true

class AddExceptionCauseToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_error_dashboard_error_logs, :exception_cause)
      add_column :rails_error_dashboard_error_logs, :exception_cause, :text
    end
  end
end
