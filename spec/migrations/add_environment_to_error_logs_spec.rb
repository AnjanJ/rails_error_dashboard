# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AddEnvironmentToErrorLogs migration" do
  let(:migration_file) do
    Dir.glob(File.join(
      RailsErrorDashboard::Engine.root, "db/migrate/*_add_environment_to_error_logs.rb"
    )).first
  end

  before { require migration_file }

  it "exists and is loadable" do
    expect(migration_file).not_to be_nil
    expect(defined?(AddEnvironmentToErrorLogs)).to eq("constant")
  end

  it "adds a 64-character environment column" do
    column = RailsErrorDashboard::ErrorLog.columns_hash["environment"]
    expect(column).not_to be_nil
    expect(column.type).to eq(:string)
    expect(column.limit).to eq(64)
    expect(column.null).to be(true)
  end

  it "adds the environment + occurred_at index" do
    expect(
      ActiveRecord::Base.connection.index_exists?(
        :rails_error_dashboard_error_logs, [ :environment, :occurred_at ],
        name: "index_error_logs_on_environment_and_occurred_at"
      )
    ).to be(true)
  end

  it "is a no-op when the column already exists (squashed-schema guard)" do
    migration = AddEnvironmentToErrorLogs.new
    migration.verbose = false
    expect { migration.migrate(:up) }.not_to raise_error
    expect(RailsErrorDashboard::ErrorLog.columns_hash).to have_key("environment")
  end
end
