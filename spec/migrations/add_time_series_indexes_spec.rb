# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AddTimeSeriesIndexes migration" do
  # Migration specs verify the migration file is valid and can be loaded.
  # BRIN and functional indexes are PostgreSQL-only and are tested in chaos tests.
  # This spec verifies the migration class exists and has the expected structure.

  let(:migration_file) do
    Dir.glob(File.join(
      RailsErrorDashboard::Engine.root, "db/migrate/*_add_time_series_indexes_to_error_logs.rb"
    )).first
  end

  it "migration file exists" do
    expect(migration_file).not_to be_nil, "Expected migration file *_add_time_series_indexes_to_error_logs.rb to exist"
  end

  it "migration file is loadable" do
    require migration_file
    expect(defined?(AddTimeSeriesIndexesToErrorLogs)).to eq("constant")
  end

  it "migration responds to change or up/down" do
    require migration_file
    migration = AddTimeSeriesIndexesToErrorLogs.new
    expect(migration).to respond_to(:up).or respond_to(:change)
  end

  it "disables DDL transaction (required for CREATE INDEX CONCURRENTLY on PostgreSQL)" do
    require migration_file
    expect(AddTimeSeriesIndexesToErrorLogs.disable_ddl_transaction).to be true
  end
end
