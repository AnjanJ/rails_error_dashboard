# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Every RED table on a connection, in an order that can be dropped.
    #
    # The tables are discovered rather than listed by hand: a hand-kept list
    # knew 5 of 13 tables, so uninstall left the rest behind (rack_attack_events
    # among them, which holds IP addresses). The order comes from the real
    # foreign keys: a table that references another is dropped first.
    #
    # Uses the raw connection only, never the models, so no model's schema
    # cache ever records a table as dropped.
    #
    # @example
    #   UninstallPlan.call(RailsErrorDashboard::ErrorLogsRecord.connection)
    #   # => [{ table: "rails_error_dashboard_error_comments", rows: 12 }, ...]
    class UninstallPlan
      PREFIX = "rails_error_dashboard_"

      class CycleError < StandardError; end

      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [Array<Hash>] { table: String, rows: Integer or nil } in drop order
      def self.call(connection)
        tables = connection.tables.select { |table| table.start_with?(PREFIX) }
        references = tables.to_h do |table|
          [ table, connection.foreign_keys(table).map(&:to_table) & tables ]
        end

        order(references).map { |table| { table: table, rows: row_count(connection, table) } }
      end

      # @param references [Hash{String => Array<String>}] each table and the tables it references
      # @return [Array<String>] every table, each before the tables it references
      # @raise [CycleError] when the foreign keys form a cycle
      def self.order(references)
        remaining = references.keys.sort
        ordered = []

        until remaining.empty?
          # Droppable once no other remaining table references it.
          droppable = remaining.reject do |table|
            remaining.any? { |other| other != table && references.fetch(other, []).include?(table) }
          end
          raise CycleError, "foreign-key cycle among: #{remaining.join(', ')}" if droppable.empty?

          ordered.concat(droppable)
          remaining -= droppable
        end

        ordered
      end

      def self.row_count(connection, table)
        connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}").to_i
      rescue ActiveRecord::ActiveRecordError
        nil
      end
      private_class_method :row_count
    end
  end
end
