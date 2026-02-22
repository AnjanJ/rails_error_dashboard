# frozen_string_literal: true

# Tier 0 time-series optimization: BRIN and functional indexes
#
# BRIN (Block Range Index) on occurred_at:
# - 99.9% smaller than B-tree (72KB vs 676MB on 100M rows)
# - Nearly identical query performance for time-range scans
# - Perfect for INSERT-heavy tables with naturally ordered timestamps
#
# Functional indexes for Groupdate:
# - Pre-compute DATE_TRUNC expressions used by group_by_day/group_by_hour
# - Up to 70x speedup on analytics dashboard queries
#
# All PostgreSQL-specific — gracefully skipped on SQLite/MySQL.
class AddTimeSeriesIndexesToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    return unless postgresql?

    # BRIN index on occurred_at for time-range scans
    # Replaces expensive B-tree sequential scans on large tables
    unless index_exists?(:rails_error_dashboard_error_logs, :occurred_at, name: "index_error_logs_on_occurred_at_brin")
      execute <<-SQL
        CREATE INDEX CONCURRENTLY index_error_logs_on_occurred_at_brin
        ON rails_error_dashboard_error_logs
        USING brin (occurred_at)
      SQL
    end

    # Functional index for daily grouping (used by group_by_day)
    unless index_exists_by_name?("index_error_logs_on_occurred_at_day")
      execute <<-SQL
        CREATE INDEX CONCURRENTLY index_error_logs_on_occurred_at_day
        ON rails_error_dashboard_error_logs
        (DATE_TRUNC('day', occurred_at))
      SQL
    end

    # Functional index for hourly grouping (used by group_by_hour)
    unless index_exists_by_name?("index_error_logs_on_occurred_at_hour")
      execute <<-SQL
        CREATE INDEX CONCURRENTLY index_error_logs_on_occurred_at_hour
        ON rails_error_dashboard_error_logs
        (DATE_TRUNC('hour', occurred_at))
      SQL
    end
  end

  def down
    return unless postgresql?

    execute "DROP INDEX IF EXISTS index_error_logs_on_occurred_at_brin"
    execute "DROP INDEX IF EXISTS index_error_logs_on_occurred_at_day"
    execute "DROP INDEX IF EXISTS index_error_logs_on_occurred_at_hour"
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase == "postgresql"
  end

  def index_exists_by_name?(name)
    ActiveRecord::Base.connection.execute(
      "SELECT 1 FROM pg_indexes WHERE indexname = '#{name}'"
    ).any?
  end
end
