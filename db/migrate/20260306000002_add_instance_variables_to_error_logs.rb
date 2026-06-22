# frozen_string_literal: true

class AddInstanceVariablesToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    return if column_exists?(:rails_error_dashboard_error_logs, :instance_variables)

    add_column :rails_error_dashboard_error_logs, :instance_variables, :text
  end

  def down
    remove_column :rails_error_dashboard_error_logs, :instance_variables if column_exists?(:rails_error_dashboard_error_logs, :instance_variables)
  end
end
