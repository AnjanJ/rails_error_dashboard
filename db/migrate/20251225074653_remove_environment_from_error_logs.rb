class RemoveEnvironmentFromErrorLogs < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration ran (column never existed) or already removed
    return unless column_exists?(:rails_error_dashboard_error_logs, :environment)

    # Only the v0.1.x column is removed: it was NOT NULL. The column
    # AddEnvironmentToErrorLogs adds back (0.11.0) is nullable and holds real
    # data. This migration replays over it whenever RED's migrations run
    # against tables that already exist (an app joining a shared error
    # database runs its own renumbered copy of every migration), and dropping
    # it there wiped every error's environment.
    environment = columns(:rails_error_dashboard_error_logs).find { |column| column.name == "environment" }
    return if environment.nil? || environment.null

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
