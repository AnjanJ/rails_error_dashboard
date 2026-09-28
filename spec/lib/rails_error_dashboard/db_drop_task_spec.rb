# frozen_string_literal: true

require "rails_helper"
require "rake"

# The task used to know 5 of RED's 13 tables and dropped them in reverse
# order, error_logs first, so with data present the foreign keys stopped it.
# It also always used the primary connection. These examples run the real
# task against the real tables inside a savepoint that is rolled back.
RSpec.describe "rails_error_dashboard:db:drop rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("rails_error_dashboard:db:drop")
  end

  let(:task) { Rake::Task["rails_error_dashboard:db:drop"] }

  before do
    task.reenable
  end

  def run_task(confirmation)
    allow($stdin).to receive(:gets).and_return("#{confirmation}\n")
    capture_stdout { task.invoke }
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it "drops every RED table, with rows behind every foreign key" do
    with_rolled_back_ddl do |connection|
      seed_one_row_per_foreign_key
      tables = red_tables(connection)

      output = run_task("DELETE ALL DATA")

      expect(red_tables(connection)).to be_empty
      tables.each { |table| expect(output).to include(table) }
    end
  end

  it "keeps the host app's own tables" do
    with_rolled_back_ddl do |connection|
      others = connection.tables.grep_v(RedTableDropHelpers::RED_TABLE)

      run_task("DELETE ALL DATA")

      expect(connection.tables.grep_v(RedTableDropHelpers::RED_TABLE)).to match_array(others)
    end
  end

  it "drops nothing unless the confirmation matches" do
    with_rolled_back_ddl do |connection|
      tables = red_tables(connection)

      output = run_task("no")

      expect(red_tables(connection)).to eq(tables)
      expect(output).to include("Cancelled")
    end
  end

  it "warns that every application's errors go in a shared database" do
    with_rolled_back_ddl do
      create(:application, name: "BillingApp")
      create(:application, name: "StorefrontApp")

      output = run_task("no")

      expect(output).to include("BillingApp", "StorefrontApp")
    end
  end

  context "when use_separate_database is on but RED is connected to the primary database" do
    around do |example|
      config = RailsErrorDashboard.configuration
      original = [ config.use_separate_database, config.database ]
      config.use_separate_database = true
      config.database = :error_dashboard
      example.run
    ensure
      config.use_separate_database, config.database = original
    end

    it "refuses, naming the missing database.yml entry, and drops nothing" do
      tables = red_tables

      expect { run_task("DELETE ALL DATA") }
        .to raise_error(RailsErrorDashboard::Commands::DropAllTables::Error, /error_dashboard/)
      expect(red_tables).to eq(tables)
    end
  end
end
