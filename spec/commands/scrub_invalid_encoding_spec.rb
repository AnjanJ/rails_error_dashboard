# frozen_string_literal: true

require "rails_helper"
require "rake"

# Rows stored before captures were scrubbed. SQLite and MySQL accept invalid
# UTF-8, so the bytes sit in the table and break the pages that render them.
RSpec.describe RailsErrorDashboard::Commands::ScrubInvalidEncoding do
  let!(:application) { create(:application) }
  let(:connection) { RailsErrorDashboard::ErrorLog.connection }
  let(:sqlite) { connection.adapter_name.match?(/sqlite/i) }

  # "bad \xFF\xFE\x00 row" written as raw bytes, bypassing ActiveRecord.
  def poison(table, column, id)
    hex = "bad \xFF\xFE row".b.unpack1("H*")
    connection.execute("UPDATE #{table} SET #{column} = CAST(X'#{hex}' AS TEXT) WHERE id = #{id.to_i}")
  end

  # The bytes as the database holds them. The model scrubs on load, so reading
  # through it can no longer show whether a row is still bad on disk.
  def stored(table, column, id)
    connection.select_value("SELECT #{column} FROM #{table} WHERE id = #{id.to_i}")
  end

  before { skip "raw invalid bytes can only be stored on SQLite here" unless sqlite }

  it "repairs an invalid error log and reports the counts" do
    clean = create(:error_log, application: application, message: "fine")
    dirty = create(:error_log, application: application, message: "placeholder")
    poison("rails_error_dashboard_error_logs", "message", dirty.id)
    expect(stored("rails_error_dashboard_error_logs", "message", dirty.id)).not_to be_valid_encoding
    # Readable straight away, before any repair: the model scrubs on load.
    expect(RailsErrorDashboard::ErrorLog.find(dirty.id).message).to eq("bad ?? row")

    result = described_class.call

    expect(result[:repaired]).to eq(1)
    expect(result[:scanned]).to be >= 2
    expect(result[:unreadable]).to eq([])
    expect(stored("rails_error_dashboard_error_logs", "message", dirty.id)).to eq("bad ?? row")
    expect(RailsErrorDashboard::ErrorLog.find(clean.id).message).to eq("fine")
  end

  it "does not touch updated_at on the rows it repairs" do
    dirty = create(:error_log, application: application)
    poison("rails_error_dashboard_error_logs", "message", dirty.id)
    before_time = RailsErrorDashboard::ErrorLog.find(dirty.id).updated_at

    described_class.call

    expect(RailsErrorDashboard::ErrorLog.find(dirty.id).updated_at).to eq(before_time)
  end

  it "repairs occurrences too" do
    error = create(:error_log, application: application)
    occurrence = RailsErrorDashboard::ErrorOccurrence.create!(error_log: error, occurred_at: Time.current, session_id: "x")
    poison("rails_error_dashboard_error_occurrences", "session_id", occurrence.id)

    result = described_class.call

    expect(result[:repaired]).to eq(1)
    expect(RailsErrorDashboard::ErrorOccurrence.find(occurrence.id).session_id).to be_valid_encoding
  end

  it "finds nothing to repair on a second run" do
    dirty = create(:error_log, application: application)
    poison("rails_error_dashboard_error_logs", "message", dirty.id)

    described_class.call
    second = described_class.call

    expect(second[:repaired]).to eq(0)
  end

  it "works across batch boundaries" do
    rows = Array.new(5) { create(:error_log, application: application) }
    rows.each { |row| poison("rails_error_dashboard_error_logs", "message", row.id) }

    result = described_class.call(batch_size: 2)

    expect(result[:repaired]).to eq(5)
  end

  it "reports a row it cannot repair by id and carries on" do
    first = create(:error_log, application: application)
    second = create(:error_log, application: application)
    [ first, second ].each { |row| poison("rails_error_dashboard_error_logs", "message", row.id) }
    allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:update_columns).and_wrap_original do |original, *args|
      raise ActiveRecord::StatementInvalid, "boom" if original.receiver.id == first.id

      original.call(*args)
    end

    result = described_class.call

    expect(result[:repaired]).to eq(1)
    expect(result[:unreadable]).to eq([ "ErrorLog##{first.id} (ActiveRecord::StatementInvalid)" ])
  end

  describe "rake error_dashboard:scrub_invalid_encoding", type: :request do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("error_dashboard:scrub_invalid_encoding") }

    it "prints the counts and repairs what is stored" do
      RailsErrorDashboard.configuration.authenticate_with = -> { true }
      dirty = create(:error_log, application: application)
      poison("rails_error_dashboard_error_logs", "message", dirty.id)

      # The page renders even before the repair, because the model scrubs on
      # load. What the task fixes is the bytes on disk, which anything that
      # does not go through the model (raw SQL, exports, other tools) still sees.
      get "/error_dashboard/errors/#{dirty.id}"
      expect(response).to have_http_status(:ok)
      expect(stored("rails_error_dashboard_error_logs", "message", dirty.id)).not_to be_valid_encoding

      task = Rake::Task["error_dashboard:scrub_invalid_encoding"]
      task.reenable
      expect { task.invoke }.to output(/repaired:\s+1\n\s+unreadable:\s+0/).to_stdout

      get "/error_dashboard/errors/#{dirty.id}"
      expect(response).to have_http_status(:ok)
      expect(stored("rails_error_dashboard_error_logs", "message", dirty.id)).to be_valid_encoding
    ensure
      RailsErrorDashboard.configuration.authenticate_with = nil
    end
  end
end
