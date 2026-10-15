# frozen_string_literal: true

require "rails_helper"

# occurrence-context-history/REQ-12: the table that keeps each occurrence's
# moment-of-failure context, in the error database.
RSpec.describe "CreateRailsErrorDashboardErrorOccurrenceContexts migration" do
  let(:migration_file) do
    Dir.glob(File.join(
      RailsErrorDashboard::Engine.root, "db/migrate/*_create_rails_error_dashboard_error_occurrence_contexts.rb"
    )).first
  end
  let(:table) { :rails_error_dashboard_error_occurrence_contexts }
  let(:connection) { RailsErrorDashboard::ErrorLogsRecord.connection }

  it "exists and is loadable" do
    expect(migration_file).not_to be_nil
    require migration_file
    expect(defined?(CreateRailsErrorDashboardErrorOccurrenceContexts)).to eq("constant")
  end

  it "creates the table with the error row's four context columns" do
    columns = connection.columns(table).index_by(&:name)

    expect(columns["error_occurrence_id"]).to have_attributes(type: :integer, null: false)
    expect(columns["error_log_id"]).to have_attributes(type: :integer, null: false)
    %w[breadcrumbs system_health local_variables instance_variables].each do |name|
      expect(columns[name]&.type).to eq(:text), "#{name} should be text"
    end
    expect(columns["created_at"]).to be_present
  end

  it "makes one context per occurrence and indexes the error for trimming" do
    expect(connection.index_exists?(table, :error_occurrence_id, unique: true)).to be(true)
    expect(connection.index_exists?(table, :error_log_id)).to be(true)
  end
end
