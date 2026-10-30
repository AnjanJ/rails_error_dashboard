# frozen_string_literal: true

# up/down rather than `change`: the index_exists? guard that makes `up` safe
# to re-run would make a reversed `change` skip the removal.
class AddAdditionalPerformanceIndexes < ActiveRecord::Migration[7.0]
  def up
    # Skip if squashed migration already added these indexes
    return if index_exists?(:rails_error_dashboard_error_logs, [ :assigned_to, :status, :occurred_at ],
                            name: 'index_error_logs_on_assignment_workflow')

    # Composite index for workflow filtering (assigned errors with status)
    # Common query: WHERE assigned_to = ? AND status = ? ORDER BY occurred_at DESC
    # Used in: "Show me all errors assigned to John that are investigating"
    add_index :rails_error_dashboard_error_logs, [ :assigned_to, :status, :occurred_at ],
              name: 'index_error_logs_on_assignment_workflow',
              if_not_exists: true

    # Composite index for priority filtering with resolution status
    # Common query: WHERE priority_level = ? AND resolved = ? ORDER BY occurred_at DESC
    # Used in: "Show me all high priority unresolved errors"
    add_index :rails_error_dashboard_error_logs, [ :priority_level, :resolved, :occurred_at ],
              name: 'index_error_logs_on_priority_resolution',
              if_not_exists: true

    # Composite index for platform + status filtering (common in analytics)
    # Common query: WHERE platform = ? AND status = ? ORDER BY occurred_at DESC
    # Used in: "Show me all iOS errors that are new"
    add_index :rails_error_dashboard_error_logs, [ :platform, :status, :occurred_at ],
              name: 'index_error_logs_on_platform_status_time',
              if_not_exists: true

    # Composite index for version-based filtering
    # Common query: WHERE app_version = ? AND resolved = ? ORDER BY occurred_at DESC
    # Used in: "Show me all unresolved errors in version 2.1.0"
    add_index :rails_error_dashboard_error_logs, [ :app_version, :resolved, :occurred_at ],
              name: 'index_error_logs_on_version_resolution_time',
              if_not_exists: true

    # Composite index for snooze management
    # Common query: WHERE snoozed_until IS NOT NULL AND snoozed_until < NOW()
    # Used in: Finding errors that need to be unsnoozed
    add_index :rails_error_dashboard_error_logs, [ :snoozed_until, :occurred_at ],
              name: 'index_error_logs_on_snooze_time',
              where: "snoozed_until IS NOT NULL",
              if_not_exists: true

    # Composite index for error hash lookups with time window
    # Common query: WHERE error_hash = ? AND occurred_at >= ?
    # Used in: Similar error detection within time windows
    # Note: There's already an index on [error_hash, resolved, occurred_at]
    # but this one is for time-based similarity without resolved filter

    # Add GIN index for backtrace full-text search (PostgreSQL only)
    # Improves search performance across both message and backtrace
    if postgresql?
      reversible do |dir|
        dir.up do
          execute <<-SQL
            CREATE INDEX IF NOT EXISTS index_error_logs_on_searchable_text
            ON rails_error_dashboard_error_logs
            USING gin(to_tsvector('english',
              COALESCE(message, '') || ' ' ||
              COALESCE(backtrace, '') || ' ' ||
              COALESCE(error_type, '')
            ))
          SQL
        end
      end
    end
  end

  def down
    return unless table_exists?(:rails_error_dashboard_error_logs)

    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_assignment_workflow', if_exists: true
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_priority_resolution', if_exists: true
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_platform_status_time', if_exists: true
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_version_resolution_time', if_exists: true
    remove_index :rails_error_dashboard_error_logs, name: 'index_error_logs_on_snooze_time', if_exists: true

    execute "DROP INDEX IF EXISTS index_error_logs_on_searchable_text" if postgresql?
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql'
  end
end
