# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CreateRailsErrorDashboardCompleteSchema migration" do
  let(:migration_file) do
    Dir.glob(File.join(
      RailsErrorDashboard::Engine.root, "db/migrate/*_create_rails_error_dashboard_complete_schema.rb"
    )).first
  end
  let(:generators) { Rails.configuration.generators }

  before { require migration_file }

  def user_id_types_on_fresh_install
    types = nil
    with_rolled_back_ddl do |connection|
      RailsErrorDashboard::Commands::DropAllTables.call(connection: connection)
      migration = CreateRailsErrorDashboardCompleteSchema.new
      migration.verbose = false
      migration.exec_migration(connection, :up)

      types = %w[rails_error_dashboard_error_logs rails_error_dashboard_error_occurrences].map do |table|
        column = connection.columns(table).find { |c| c.name == "user_id" }
        # SQLite reports a bigint column with no limit, so read the SQL type:
        # "bigint" on SQLite, PostgreSQL and MySQL alike.
        column.sql_type.downcase.start_with?("bigint") ? :bigint : column.type
      end
    end
    types
  end

  def primary_key_type(type)
    allow(generators).to receive(:options).and_return(generators.orm => { primary_key_type: type })
  end

  # A 4-byte user_id loses ids over 2**31 - 1 (hardening-1-0-rc2/REQ-15), so a
  # fresh install without primary_key_type gets bigint.
  it "types user_id as bigint by default (hardening-1-0-rc2/REQ-16)" do
    expect(user_id_types_on_fresh_install).to all(eq(:bigint))
  end

  it "types user_id like the app's primary keys" do
    primary_key_type(:string)

    expect(user_id_types_on_fresh_install).to all(eq(:string))
  end

  it "types user_id as uuid when the app's primary keys are UUIDs (hardening-1-0-rc2/REQ-16)" do
    skip "no uuid column type on this database" unless RailsErrorDashboard::ErrorLogsRecord.connection.native_database_types.key?(:uuid)
    primary_key_type(:uuid)

    expect(user_id_types_on_fresh_install).to all(eq(:uuid))
  end
end
