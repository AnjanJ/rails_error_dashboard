# frozen_string_literal: true

require "rails_helper"

migration_path = Dir[
  RailsErrorDashboard::Engine.root.join("db/migrate/*_add_last_notified_at_to_error_logs.rb")
].first
require migration_path if migration_path

# This migration ships in the gem and the installer copies it into the host
# app, so it is executed here rather than only asserted against the schema:
# a failure in its body aborts `rails db:migrate` for a real user.
#
# It runs against a throwaway table (TABLE is stubbed). Dropping a column from
# the real error_logs table on SQLite rebuilds the table, and that is not a
# thing to do to the suite's schema from inside an example.
RSpec.describe "AddLastNotifiedAtToErrorLogs", type: :migration do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:table) { :red_last_notified_at_spec }
  let(:migration) do
    ActiveRecord::Migration.suppress_messages { AddLastNotifiedAtToErrorLogs.new }
  end

  def run(direction)
    ActiveRecord::Migration.suppress_messages { migration.migrate(direction) }
  end

  def column
    connection.columns(table).find { |c| c.name == "last_notified_at" }
  end

  before do
    expect(migration_path).to be_present, "db/migrate/*_add_last_notified_at_to_error_logs.rb is missing"
    stub_const("AddLastNotifiedAtToErrorLogs::TABLE", table)
    connection.create_table(table, force: true) { |t| t.string :error_hash }
  end

  after { connection.drop_table(table, if_exists: true) }

  it "adds a nullable datetime with no default" do
    run(:up)

    expect(column).to be_present
    expect(column.type).to eq(:datetime)
    expect(column.null).to be true
    expect(column.default).to be_nil
  end

  it "adds no index (rows are claimed by primary key)" do
    run(:up)

    expect(connection.indexes(table).flat_map { |i| Array(i.columns) }).not_to include("last_notified_at")
  end

  it "is idempotent: a second run is a no-op, not a duplicate-column error" do
    run(:up)

    expect { run(:up) }.not_to raise_error
  end

  it "is reversible, and reversing twice does not raise" do
    run(:up)
    run(:down)

    expect(column).to be_nil
    expect { run(:down) }.not_to raise_error
  end

  it "does nothing when the table does not exist" do
    connection.drop_table(table)

    expect { run(:up) }.not_to raise_error
    expect { run(:down) }.not_to raise_error
  end

  # A timestamp ahead of the clock sorts after migrations a host generates
  # today, and Rails then refuses to run the "older" ones without a flag.
  it "does not carry a version from the future" do
    version = File.basename(migration_path)[/\A\d{14}/]

    expect(Time.utc(*version.unpack("a4a2a2a2a2a2").map(&:to_i))).to be <= Time.now.utc
  end

  it "is mirrored by the test schema" do
    RailsErrorDashboard::ErrorLog.reset_column_information

    expect(RailsErrorDashboard::ErrorLog.column_names).to include("last_notified_at")
  end
end
