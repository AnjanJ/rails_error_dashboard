# up/down rather than `change`: the column_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddControllerActionToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added these columns
    return if column_exists?(:rails_error_dashboard_error_logs, :controller_name)

    add_column :rails_error_dashboard_error_logs, :controller_name, :string
    add_column :rails_error_dashboard_error_logs, :action_name, :string

    # Add composite index for efficient querying by controller/action
    add_index :rails_error_dashboard_error_logs, [ :controller_name, :action_name, :error_hash ],
              name: 'index_error_logs_on_controller_action_hash'
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_controller_action_hash', if_exists: true
    remove_column :rails_error_dashboard_error_logs, :controller_name, if_exists: true
    remove_column :rails_error_dashboard_error_logs, :action_name, if_exists: true
  end
end
