class AddControllerActionToErrorLogs < ActiveRecord::Migration[8.1]
  def change
    # Skip if squashed migration already ran
    return if connection.table_exists?(:rails_error_dashboard_schema_markers)

    add_column :rails_error_dashboard_error_logs, :controller_name, :string
    add_column :rails_error_dashboard_error_logs, :action_name, :string

    # Add composite index for efficient querying by controller/action
    add_index :rails_error_dashboard_error_logs, [ :controller_name, :action_name, :error_hash ],
              name: 'index_error_logs_on_controller_action_hash'
  end
end
