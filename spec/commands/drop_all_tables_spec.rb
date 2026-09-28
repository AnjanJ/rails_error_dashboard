# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::DropAllTables do
  describe ".call" do
    it "drops every RED table, with rows behind every foreign key" do
      with_rolled_back_ddl do |connection|
        seed_one_row_per_foreign_key
        expected = red_tables(connection)

        dropped = described_class.call(connection: connection)

        expect(dropped).to match_array(expected)
        expect(red_tables(connection)).to be_empty
      end
    end

    it "leaves the host app's own tables alone" do
      with_rolled_back_ddl do |connection|
        others = connection.tables.grep_v(RedTableDropHelpers::RED_TABLE)

        described_class.call(connection: connection)

        expect(connection.tables.grep_v(RedTableDropHelpers::RED_TABLE)).to match_array(others)
      end
    end

    it "drops nothing when a host table has a foreign key into a RED table, and names it" do
      with_rolled_back_ddl do |connection|
        connection.create_table(:host_invoices) { |t| t.references :error_log }
        connection.add_foreign_key(:host_invoices, :rails_error_dashboard_error_logs, column: :error_log_id)
        tables = red_tables(connection)

        expect { described_class.call(connection: connection) }
          .to raise_error(described_class::Error, /host_invoices/)
        expect(red_tables(connection)).to eq(tables)
      end
    end
  end

  describe ".connection" do
    it "is the connection RED's models use" do
      expect(described_class.connection).to equal(RailsErrorDashboard::ErrorLogsRecord.connection)
    end

    context "when use_separate_database is on but RED is connected elsewhere" do
      around do |example|
        config = RailsErrorDashboard.configuration
        original = [ config.use_separate_database, config.database ]
        config.use_separate_database = true
        config.database = :error_dashboard
        example.run
      ensure
        config.use_separate_database, config.database = original
      end

      it "refuses, naming the database.yml entry that is missing" do
        expect { described_class.connection }
          .to raise_error(described_class::Error, /error_dashboard.*database\.yml/m)
      end
    end
  end
end
