# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Drops every RED table, for uninstalling. DESTRUCTIVE: all error data goes.
    #
    # Used by the rails_error_dashboard:db:drop task and the uninstall
    # generator. Drops on the connection RED's models use, so a separate or
    # shared error database is covered, in the order Queries::UninstallPlan
    # derives from the foreign keys. Where the adapter runs DDL in a transaction
    # (PostgreSQL, SQLite) it is all-or-nothing. Errors are raised, never
    # swallowed: a half-finished uninstall must not report success.
    #
    # @example
    #   RailsErrorDashboard::Commands::DropAllTables.call
    #   # => ["rails_error_dashboard_error_comments", ...]
    class DropAllTables
      class Error < StandardError; end

      # The connection RED's models use.
      #
      # @raise [Error] when use_separate_database is on but the engine fell back
      #   to the primary database because database.yml has no entry for it:
      #   dropping there would leave the real error database untouched.
      # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      def self.connection
        config = RailsErrorDashboard.configuration
        record = RailsErrorDashboard::ErrorLogsRecord

        if config.use_separate_database
          expected = config.database.to_s
          actual = record.connection_db_config&.name.to_s
          if actual != expected
            raise Error, "use_separate_database is on, but RED is connected to the '#{actual}' database, " \
                         "not '#{expected}': database.yml has no '#{expected}' entry for #{Rails.env}. " \
                         "Add it (see docs/guides/DATABASE_OPTIONS.md) and run this again, or RED's tables " \
                         "in the error database would be left behind."
          end
        end

        record.connection
      end

      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [Array<String>] the dropped tables, in drop order
      # @raise [Error] when a host table has a foreign key into a RED table
      def self.call(connection: self.connection)
        tables = Queries::UninstallPlan.call(connection).map { |entry| entry[:table] }
        return [] if tables.empty?

        blocking = host_foreign_keys(connection, tables)
        if blocking.any?
          raise Error, "Not dropping anything: these tables have foreign keys into RED's tables. " \
                       "Remove the foreign keys first: #{blocking.join('; ')}"
        end

        drop = -> { tables.each { |table| connection.drop_table(table, if_exists: true) } }
        if connection.supports_ddl_transactions?
          connection.transaction(requires_new: true) { drop.call }
        else
          drop.call
        end

        tables
      end

      def self.host_foreign_keys(connection, tables)
        (connection.tables - tables).flat_map do |table|
          connection.foreign_keys(table)
            .select { |fk| tables.include?(fk.to_table) }
            .map { |fk| "#{table}.#{fk.column} -> #{fk.to_table} (#{fk.name})" }
        end
      end
      private_class_method :host_foreign_keys
    end
  end
end
