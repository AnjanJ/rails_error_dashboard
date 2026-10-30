class AddApplicationToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added this column
    return if column_exists?(:rails_error_dashboard_error_logs, :application_id)

    # Add nullable column first (for existing records)
    add_column :rails_error_dashboard_error_logs, :application_id, :bigint

    # Add indexes for performance
    add_index :rails_error_dashboard_error_logs, :application_id

    add_index :rails_error_dashboard_error_logs,
              [ :application_id, :occurred_at ],
              name: 'index_error_logs_on_app_occurred'

    add_index :rails_error_dashboard_error_logs,
              [ :application_id, :resolved ],
              name: 'index_error_logs_on_app_resolved'
  end

  def down
    # PostgreSQL would drop this index with the column and say nothing, and no up
    # puts it back. It's what stops duplicate error groups.
    if index_name_exists?(:rails_error_dashboard_error_logs, "index_error_logs_on_group_identity")
      raise ActiveRecord::MigrationError, "index_error_logs_on_group_identity needs application_id, and nothing would put it back"
    end

    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_app_resolved'
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_app_occurred'
    remove_index :rails_error_dashboard_error_logs, column: :application_id
    remove_column :rails_error_dashboard_error_logs, :application_id
  end
end
