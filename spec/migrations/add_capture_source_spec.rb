# frozen_string_literal: true

require "rails_helper"

# capture-source/REQ-9: where each capture came from, on the occurrence and on
# the error row's shown backtrace.
RSpec.describe "AddCaptureSourceToErrorOccurrencesAndErrorLogs migration" do
  let(:migration_file) do
    Dir.glob(File.join(
      RailsErrorDashboard::Engine.root, "db/migrate/*_add_capture_source_to_error_occurrences_and_error_logs.rb"
    )).first
  end
  let(:connection) { RailsErrorDashboard::ErrorLogsRecord.connection }

  def column(table, name)
    connection.columns(table).find { |c| c.name == name }
  end

  it "exists and is loadable" do
    expect(migration_file).not_to be_nil
    require migration_file
    expect(defined?(AddCaptureSourceToErrorOccurrencesAndErrorLogs)).to eq("constant")
  end

  it "adds a nullable capture_source to occurrences and backtrace_source to errors" do
    { rails_error_dashboard_error_occurrences: "capture_source",
      rails_error_dashboard_error_logs: "backtrace_source" }.each do |table, name|
      expect(column(table, name)).to have_attributes(type: :string, null: true, default: nil, limit: 10),
        "#{table}.#{name} should be a nullable string(10)"
    end
  end

  it "does nothing when run again" do
    require migration_file

    expect {
      ActiveRecord::Migration.suppress_messages { AddCaptureSourceToErrorOccurrencesAndErrorLogs.new.migrate(:up) }
    }.not_to raise_error
  end
end
