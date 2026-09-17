# frozen_string_literal: true

require "rails_helper"

# An exception can carry bytes that are not valid UTF-8: a binary upload echoed
# into a message, a Latin-1 query string, a NUL from a fuzzer. Those bytes must
# never stop the capture (sync, async or storm), and what is stored must be
# valid — otherwise the error that most needs looking at is the one whose page
# answers 500.
RSpec.describe "capturing errors that contain invalid bytes" do
  let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:bad) { "\xFF\xFE" }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.sampling_rate = 1.0
    config.async_logging = false
    config.enable_storm_protection = false
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    gate.reset!
  end

  def hostile_error(message = "upload failed: caf\xC3 #{bad} password=hunter2 \0end".b)
    error = begin
      begin
        raise IOError, "cause #{bad} \0".b
      rescue IOError
        raise RuntimeError, message # carries the IOError as its cause
      end
    rescue RuntimeError => e
      e
    end
    error.set_backtrace([
      "#{Rails.root}/app/models/upload.rb:12:in 'read_#{bad}'".b,
      "#{Rails.root}/app/controllers/uploads_controller.rb:7:in 'create'"
    ])
    error
  end

  def hostile_context
    {
      request_url: "https://shop.test/uploads?name=#{bad}".b,
      user_agent: "Mozilla/5.0 #{bad}".b,
      params: { "file#{bad}".b => "v#{bad}".b, nested: { deep: [ "x#{bad}\0".b ] } },
      controller_name: "uploads",
      action_name: "create",
      session_id: "sess#{bad}".b,
      request_id: "req#{bad}".b
    }
  end

  def invalid_strings_in(record)
    record.attributes.select { |_name, value| value.is_a?(String) && !value.valid_encoding? }.keys
  end

  def nul_strings_in(record)
    record.attributes.select { |_name, value| value.is_a?(String) && value.include?("\0") }.keys
  end

  describe "the sync path" do
    it "returns the stored row, and every String on it is valid" do
      row = RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)

      expect(row).to be_a(logs)
      expect(row).to be_persisted
      stored = logs.find(row.id)
      expect(invalid_strings_in(stored)).to eq([])
      expect(nul_strings_in(stored)).to eq([])
      expect(stored.message).to include("upload failed: caf")
      expect(stored.exception_cause).to include("IOError")
    end

    # A string TAGGED UTF-8 but holding invalid bytes is the nastier variant:
    # every regex match on it raises ArgumentError, where a binary-tagged
    # string only fails once it meets JSON or the database.
    it "captures a message that is tagged UTF-8 but is not valid UTF-8" do
      message = (+"tagged utf-8 \xFF\xFE token=abc123").force_encoding(Encoding::UTF_8)
      context = hostile_context.transform_values { |v| v.is_a?(String) ? v.dup.force_encoding(Encoding::UTF_8) : v }

      row = RailsErrorDashboard::Commands::LogError.call(hostile_error(message), context)

      expect(row).to be_a(logs)
      expect(invalid_strings_in(logs.find(row.id))).to eq([])
      expect(logs.find(row.id).message).to start_with("tagged utf-8 ??")
    end

    it "stores a valid occurrence row too" do
      row = RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)

      occurrence = RailsErrorDashboard::ErrorOccurrence.where(error_log_id: row.id).sole
      expect(invalid_strings_in(occurrence)).to eq([])
    end

    it "still redacts after scrubbing" do
      row = RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)

      expect(logs.find(row.id).message).not_to include("hunter2")
    end

    it "groups a second identical capture onto the same row" do
      first = RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)
      second = RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)

      expect(second.id).to eq(first.id)
      expect(logs.count).to eq(1)
    end

    it "stores valid breadcrumbs" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
      RailsErrorDashboard::Services::BreadcrumbCollector.add("custom", "crumb #{bad}".b, metadata: { "k" => "v#{bad}".b })

      row = RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)

      stored = logs.find(row.id)
      expect(stored.breadcrumbs).to be_present
      expect(stored.breadcrumbs).to be_valid_encoding
      expect { JSON.parse(stored.breadcrumbs) }.not_to raise_error
    ensure
      RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
    end

    it "does not change a clean capture" do
      clean = RuntimeError.new("plain message")
      clean.set_backtrace([ "#{Rails.root}/app/models/a.rb:1:in 'x'" ])

      row = RailsErrorDashboard::Commands::LogError.call(clean, request_url: "https://shop.test/ok")

      expect(row.message).to eq("plain message")
      expect(row.request_url).to eq("https://shop.test/ok")
    end
  end

  describe "the async path" do
    before { RailsErrorDashboard.configuration.async_logging = true }

    it "enqueues a job whose arguments serialize" do
      RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)

      job = enqueued_jobs.find { |j| j[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
      expect(job).to be_present
      expect { job.fetch(:args).to_json }.not_to raise_error
      expect(job.fetch(:args).to_json).to be_valid_encoding
    end

    it "stores a valid row when the job runs, on the same row as a sync capture" do
      RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)
      perform_enqueued_jobs

      row = logs.sole
      expect(invalid_strings_in(row)).to eq([])
      expect(row.exception_cause).to include("IOError")

      RailsErrorDashboard.configuration.async_logging = false
      RailsErrorDashboard::Commands::LogError.call(hostile_error, hostile_context)
      expect(logs.count).to eq(1)
    end
  end

  describe "the storm gate" do
    before do
      RailsErrorDashboard.configuration.enable_storm_protection = true
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)
    end

    it "keeps a valid exemplar message while shedding" do
      gate.admit!(hostile_error, hostile_context)
      snapshot = gate.count_buffer.snapshot!

      entry = snapshot[:entries].sole
      expect(entry["message"]).to be_valid_encoding
      expect(entry["message"]).not_to include("\0")
      expect { snapshot.to_json }.not_to raise_error
      expect(snapshot.to_json).to be_valid_encoding
    end
  end
end

RSpec.describe "pages for an error that contains invalid bytes", type: :request do
  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.sampling_rate = 1.0
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.enable_platform_comparison = true
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
  end

  it "renders the show page, the list and platform comparison" do
    error = RuntimeError.new("render me \xFF\xFE \0".b)
    error.set_backtrace([ "#{Rails.root}/app/models/upload.rb:12:in 'read_\xFF'".b ])
    row = RailsErrorDashboard::Commands::LogError.call(
      error,
      request_url: "https://shop.test/?q=\xFF".b, user_agent: "UA \xFF".b,
      params: { "k\xFF".b => "v\xFF".b }
    )
    expect(row).to be_present

    get "/error_dashboard/errors/#{row.id}"
    expect(response).to have_http_status(:ok)

    get "/error_dashboard/errors"
    expect(response).to have_http_status(:ok)

    get "/error_dashboard/errors/platform_comparison"
    expect(response).to have_http_status(:ok)
  end
end
