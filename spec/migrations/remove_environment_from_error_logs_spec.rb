# frozen_string_literal: true

require "rails_helper"

# RemoveEnvironmentFromErrorLogs dropped the v0.1.x environment column during
# the v1.0 refactor. AddEnvironmentToErrorLogs (0.11.0) brought a new, nullable
# column back. Any replay of RED's migrations over existing tables -- an app
# joining a shared error database runs its renumbered copies of every
# migration -- must not drop the new column, or every error loses its
# environment. remove_column/remove_index are stubbed so a regression can't
# damage the test database.
RSpec.describe "RemoveEnvironmentFromErrorLogs migration" do
  let(:migration_file) do
    Dir.glob(File.join(
      RailsErrorDashboard::Engine.root, "db/migrate/*_remove_environment_from_error_logs.rb"
    )).first
  end
  let(:migration) { RemoveEnvironmentFromErrorLogs.new.tap { |m| m.verbose = false } }
  let(:connection) { migration.connection }
  # Migration forwards table names to the connection as Strings.
  let(:table) { "rails_error_dashboard_error_logs" }

  before do
    require migration_file
    allow(connection).to receive(:remove_column)
    allow(connection).to receive(:remove_index)
  end

  it "keeps the nullable environment column that 0.11.0 added, when replayed" do
    expect(RailsErrorDashboard::ErrorLog.columns_hash["environment"].null).to be(true)

    migration.migrate(:up)

    expect(connection).not_to have_received(:remove_column)
    expect(connection).not_to have_received(:remove_index)
  end

  it "still removes the v0.1.x NOT NULL environment column" do
    legacy = instance_double(ActiveRecord::ConnectionAdapters::Column, name: "environment", null: false)
    allow(connection).to receive(:columns).and_call_original
    allow(connection).to receive(:columns).with(table).and_return([ legacy ])

    migration.migrate(:up)

    expect(connection).to have_received(:remove_column)
      .with(table, :environment, :string)
  end

  it "does nothing when there is no environment column" do
    allow(connection).to receive(:column_exists?).and_call_original
    allow(connection).to receive(:column_exists?)
      .with(table, :environment).and_return(false)
    allow(connection).to receive(:columns).and_call_original
    allow(connection).to receive(:columns).with(table).and_return([])

    migration.migrate(:up)

    expect(connection).not_to have_received(:remove_column)
  end
end
