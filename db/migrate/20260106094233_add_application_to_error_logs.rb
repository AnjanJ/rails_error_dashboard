class AddApplicationToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Add nullable column first (for existing records)
    add_column :rails_error_dashboard_error_logs, :application_id, :bigint

    # Add indexes for performance
    add_index :rails_error_dashboard_error_logs, :application_id

    add_index :rails_error_dashboard_error_logs,
              [:application_id, :occurred_at],
              name: 'index_error_logs_on_app_occurred'

    add_index :rails_error_dashboard_error_logs,
              [:application_id, :resolved],
              name: 'index_error_logs_on_app_resolved'
  end

  def down
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_app_resolved'
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_app_occurred'
    remove_index :rails_error_dashboard_error_logs, column: :application_id
    remove_column :rails_error_dashboard_error_logs, :application_id
  end
end
