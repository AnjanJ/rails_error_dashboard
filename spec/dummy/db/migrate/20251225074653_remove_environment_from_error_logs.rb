class RemoveEnvironmentFromErrorLogs < ActiveRecord::Migration[8.1]
  def up
    # Skip if squashed migration already ran
    return if connection.table_exists?(:rails_error_dashboard_schema_markers)

    # Remove composite index first
    remove_index :rails_error_dashboard_error_logs,
                 name: 'index_error_logs_on_environment_and_occurred_at',
                 if_exists: true

    # Remove single column index
    remove_index :rails_error_dashboard_error_logs,
                 column: :environment,
                 if_exists: true

    # Remove the column
    remove_column :rails_error_dashboard_error_logs, :environment, :string
  end

  def down
    # Add column back
    add_column :rails_error_dashboard_error_logs, :environment, :string, null: false, default: 'production'

    # Recreate indexes
    add_index :rails_error_dashboard_error_logs, :environment
    add_index :rails_error_dashboard_error_logs, [ :environment, :occurred_at ],
              name: 'index_error_logs_on_environment_and_occurred_at'
  end
end
