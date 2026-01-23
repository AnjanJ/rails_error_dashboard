# frozen_string_literal: true

class AddOptimizedIndexesToErrorLogs < ActiveRecord::Migration[8.1]
  def change
    # Skip if squashed migration already ran
    return if connection.table_exists?(:rails_error_dashboard_schema_markers)

    # Composite indexes for common query patterns
    # These improve performance when filtering and sorting together

    # Dashboard stats: Count unresolved errors from recent time periods
    # Query: WHERE resolved = false AND occurred_at >= ?
    add_index :rails_error_dashboard_error_logs, [ :resolved, :occurred_at ],
              name: 'index_error_logs_on_resolved_and_occurred_at'

    # Filtered lists: Show errors from specific environment ordered by time
    # Query: WHERE environment = ? ORDER BY occurred_at DESC
    add_index :rails_error_dashboard_error_logs, [ :environment, :occurred_at ],
              name: 'index_error_logs_on_environment_and_occurred_at'

    # Error type filtering with time ordering
    # Query: WHERE error_type = ? ORDER BY occurred_at DESC
    add_index :rails_error_dashboard_error_logs, [ :error_type, :occurred_at ],
              name: 'index_error_logs_on_error_type_and_occurred_at'

    # Platform filtering with time ordering
    # Query: WHERE platform = ? ORDER BY occurred_at DESC
    add_index :rails_error_dashboard_error_logs, [ :platform, :occurred_at ],
              name: 'index_error_logs_on_platform_and_occurred_at'

    # Deduplication lookup: Find existing unresolved errors by hash within 24 hours
    # Query: WHERE error_hash = ? AND resolved = false AND occurred_at >= ?
    # This is the hot path for error logging - happens on EVERY error
    add_index :rails_error_dashboard_error_logs, [ :error_hash, :resolved, :occurred_at ],
              name: 'index_error_logs_on_hash_resolved_occurred'

    # Partial index for unresolved errors (most queries filter by resolved=false)
    # Only indexes unresolved errors, making it smaller and faster
    # PostgreSQL-specific but gracefully ignored on other databases
    if postgresql?
      add_index :rails_error_dashboard_error_logs, :occurred_at,
                where: "resolved = false",
                name: 'index_error_logs_on_occurred_at_unresolved'

      # Full-text search index for message field (PostgreSQL only)
      # Dramatically improves search performance
      execute <<-SQL
        CREATE INDEX index_error_logs_on_message_gin
        ON rails_error_dashboard_error_logs
        USING gin(to_tsvector('english', message))
      SQL
    end
  end

  def down
    # Remove composite indexes
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_resolved_and_occurred_at'
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_environment_and_occurred_at'
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_error_type_and_occurred_at'
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_platform_and_occurred_at'
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_hash_resolved_occurred'

    # Remove partial/GIN indexes if PostgreSQL
    if postgresql?
      remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_occurred_at_unresolved'
      execute "DROP INDEX IF EXISTS index_error_logs_on_message_gin"
    end
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql'
  end
end
