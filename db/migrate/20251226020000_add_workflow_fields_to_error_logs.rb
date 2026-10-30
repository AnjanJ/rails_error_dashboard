# frozen_string_literal: true

# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddWorkflowFieldsToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :status)

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

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    %i[status assigned_to assigned_at snoozed_until priority_level].each do |column|
      remove_index :rails_error_dashboard_error_logs, column, if_exists: true
      remove_column :rails_error_dashboard_error_logs, column if column_exists?(:rails_error_dashboard_error_logs, column)
    end
  end
end
