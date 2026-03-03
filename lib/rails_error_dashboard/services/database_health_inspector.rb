# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Display-time only service: queries PostgreSQL system tables when the
    # DB Health page loads. NOT used in the capture path.
    #
    # Feature-detects PostgreSQL — returns nil for tables/indexes/activity
    # on SQLite/MySQL. Connection pool stats work on all adapters.
    # Every method individually rescue-wrapped (returns nil).
    class DatabaseHealthInspector
      def self.call
        new.call
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DatabaseHealthInspector failed: #{e.class}: #{e.message}")
        { adapter: nil, postgresql: false, connection_pool: nil, tables: nil,
          indexes: nil, unused_indexes: nil, activity: nil }
      end

      def call
        {
          adapter: adapter_name,
          postgresql: postgresql?,
          connection_pool: connection_pool_stats,
          tables: postgresql? ? table_stats : nil,
          indexes: postgresql? ? index_stats : nil,
          unused_indexes: postgresql? ? unused_index_stats : nil,
          activity: postgresql? ? activity_stats : nil
        }
      end

      private

      def connection
        ActiveRecord::Base.connection
      end

      def adapter_name
        connection.adapter_name
      rescue => e
        nil
      end

      def postgresql?
        adapter_name == "PostgreSQL"
      end

      def connection_pool_stats
        pool = ActiveRecord::Base.connection_pool
        stat = pool.stat
        { size: stat[:size], busy: stat[:busy], dead: stat[:dead],
          idle: stat[:idle], waiting: stat[:waiting] }
      rescue => e
        nil
      end

      def table_stats
        rows = connection.select_all(<<~SQL)
          SELECT
            schemaname,
            relname AS name,
            n_live_tup AS estimated_rows,
            pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(relname)) AS total_bytes,
            seq_scan,
            idx_scan,
            n_dead_tup AS dead_tuples,
            last_vacuum,
            last_autovacuum,
            last_analyze
          FROM pg_stat_user_tables
          ORDER BY pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(relname)) DESC
        SQL

        rows.map do |row|
          {
            name: row["name"],
            estimated_rows: row["estimated_rows"].to_i,
            total_bytes: row["total_bytes"].to_i,
            seq_scan: row["seq_scan"].to_i,
            idx_scan: row["idx_scan"].to_i,
            dead_tuples: row["dead_tuples"].to_i,
            last_vacuum: row["last_vacuum"],
            last_autovacuum: row["last_autovacuum"],
            last_analyze: row["last_analyze"],
            gem_table: row["name"].to_s.start_with?("rails_error_dashboard_")
          }
        end
      rescue => e
        nil
      end

      def index_stats
        rows = connection.select_all(<<~SQL)
          SELECT
            sui.indexrelname AS name,
            sui.relname AS table_name,
            pg_relation_size(sui.indexrelid) AS size_bytes,
            sui.idx_scan AS scans,
            sui.idx_tup_read AS tuples_read,
            sui.idx_tup_fetch AS tuples_fetched
          FROM pg_stat_user_indexes sui
          ORDER BY pg_relation_size(sui.indexrelid) DESC
        SQL

        rows.map do |row|
          {
            name: row["name"],
            table_name: row["table_name"],
            size_bytes: row["size_bytes"].to_i,
            scans: row["scans"].to_i,
            tuples_read: row["tuples_read"].to_i,
            tuples_fetched: row["tuples_fetched"].to_i
          }
        end
      rescue => e
        nil
      end

      def unused_index_stats
        rows = connection.select_all(<<~SQL)
          SELECT
            sui.indexrelname AS name,
            sui.relname AS table_name,
            pg_relation_size(sui.indexrelid) AS size_bytes
          FROM pg_stat_user_indexes sui
          WHERE sui.idx_scan = 0
            AND pg_relation_size(sui.indexrelid) > 0
          ORDER BY pg_relation_size(sui.indexrelid) DESC
        SQL

        rows.map do |row|
          {
            name: row["name"],
            table_name: row["table_name"],
            size_bytes: row["size_bytes"].to_i
          }
        end
      rescue => e
        nil
      end

      def activity_stats
        rows = connection.select_all(<<~SQL)
          SELECT
            COALESCE(state, 'unknown') AS state,
            COUNT(*) AS count,
            COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting
          FROM pg_stat_activity
          WHERE datname = current_database()
          GROUP BY state
          ORDER BY count DESC
        SQL

        by_state = rows.map do |row|
          { state: row["state"], count: row["count"].to_i, waiting: row["waiting"].to_i }
        end

        {
          by_state: by_state,
          total: by_state.sum { |r| r[:count] },
          total_waiting: by_state.sum { |r| r[:waiting] }
        }
      rescue => e
        nil
      end
    end
  end
end
