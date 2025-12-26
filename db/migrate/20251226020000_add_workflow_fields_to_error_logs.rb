# frozen_string_literal: true

class AddWorkflowFieldsToErrorLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :rails_error_dashboard_error_logs, :status, :string, default: 'new', null: false
    add_column :rails_error_dashboard_error_logs, :assigned_to, :string
    add_column :rails_error_dashboard_error_logs, :assigned_at, :datetime
    add_column :rails_error_dashboard_error_logs, :snoozed_until, :datetime
    add_column :rails_error_dashboard_error_logs, :priority_level, :integer, default: 0, null: false

    add_index :rails_error_dashboard_error_logs, :status
    add_index :rails_error_dashboard_error_logs, :assigned_to
    add_index :rails_error_dashboard_error_logs, :snoozed_until
    add_index :rails_error_dashboard_error_logs, :priority_level

    # Update existing resolved errors to have status='resolved'
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE rails_error_dashboard_error_logs
          SET status = 'resolved'
          WHERE resolved = true
        SQL
      end
    end
  end
end
