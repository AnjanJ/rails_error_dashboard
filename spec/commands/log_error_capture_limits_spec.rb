# frozen_string_literal: true

require "rails_helper"

# What every capture route stores when a value is too big for it. On MySQL in
# strict mode an oversized TEXT value made the INSERT fail, the capture path
# rescued it, and the error was silently lost -- these examples run on CI's
# MySQL row too, where "the row exists" is the real assertion.
RSpec.describe "capture size limits" do
  include ActiveJob::TestHelper

  let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:long_message) { "checkout failed " + ("x" * 70_000) }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.sampling_rate = 1.0
    config.enable_storm_protection = false
    gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    gate.reset!
  end

  def boom(message)
    error = StandardError.new(message)
    error.set_backtrace([ "#{Rails.root}/app/models/checkout.rb:12:in 'run'" ])
    error
  end

  def marker_for(message)
    "… [#{message.length - 10_000} more characters]"
  end

  describe "a message over 10,000 characters" do
    # capture-hardening-0-17/REQ-1, capture-hardening-0-17/REQ-4, capture-hardening-0-17/REQ-5
    it "is stored cut, with a marker, and groups as the full message does (sync)" do
      error = boom(long_message)
      RailsErrorDashboard::Commands::LogError.call(error)

      row = logs.sole
      expect(row.message).to eq(long_message[0, 10_000] + marker_for(long_message))
      expect(row.error_hash).to eq(
        RailsErrorDashboard::Services::ErrorHashGenerator.call(error, application_id: row.application_id)
      )
    end

    # capture-hardening-0-17/REQ-1, capture-hardening-0-17/REQ-4
    it "is cut before it crosses the queue, and stored cut (async)" do
      RailsErrorDashboard.configuration.async_logging = true
      error = boom(long_message)
      RailsErrorDashboard::Commands::LogError.call(error)

      exception_data, = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args)
      expect(exception_data["message"].length).to eq(10_000 + marker_for(long_message).length)

      perform_enqueued_jobs
      row = logs.sole
      expect(row.message).to eq(long_message[0, 10_000] + marker_for(long_message))
      # capture-hardening-0-17/REQ-5: the identity crossed the queue from the
      # raw exception, so the cut doesn't change the group.
      expect(row.error_hash).to eq(
        RailsErrorDashboard::Services::ErrorHashGenerator.call(error, application_id: row.application_id)
      )
    end

    # capture-hardening-0-17/REQ-1: redaction on the request thread can make
    # the cut message longer ("pin=1" becomes "pin=[FILTERED]"); the worker
    # must not cut it a second time and misreport how much was cut.
    it "keeps the request thread's marker when redaction made the cut message longer (async)" do
      RailsErrorDashboard.configuration.async_logging = true
      RailsErrorDashboard.configuration.filter_sensitive_data = true
      message = ("pin=1 " * 2_000) + ("x" * 70_000)

      RailsErrorDashboard::Commands::LogError.call(boom(message))
      perform_enqueued_jobs

      # The count is the request thread's. (A cut that lands inside a
      # sensitive pair lets redaction take the marker's leading ellipsis as
      # that pair's value; the count is what says how much was cut.)
      stored = logs.sole.message
      expect(stored).to end_with("[#{message.length - 10_000} more characters]")
      expect(stored).not_to include("pin=1")
    end

    # capture-hardening-0-17/REQ-4: the storm gate already keeps only the
    # first 500 characters as its exemplar, so a storm-only row stays bounded.
    it "is stored bounded when a storm only counted it" do
      RailsErrorDashboard.configuration.enable_storm_protection = true
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)

      gate.admit!(boom(long_message))
      snapshot = gate.count_buffer.snapshot!
      RailsErrorDashboard::Commands::FlushStormCounts.call(entries: snapshot[:entries], overflow: snapshot[:overflow])

      expect(logs.sole.message).to eq(long_message[0, RailsErrorDashboard::Services::ErrorHashGenerator::HASH_MESSAGE_LIMIT])
    end
  end

  # capture-hardening-0-17/REQ-2, capture-hardening-0-17/REQ-4
  it "stores request params over 64,000 bytes as valid JSON with the small values kept" do
    params = { "upload" => "u" * 70_000, "order_id" => "42" }.to_json
    RailsErrorDashboard::Commands::LogError.call(boom("params too big"), request_params: params)

    stored = logs.sole.request_params
    expect(stored.bytesize).to be <= 64_000
    expect(JSON.parse(stored)).to include("order_id" => "42", "upload" => "[TRUNCATED]", "_truncated" => true)
  end

  # capture-hardening-0-17/REQ-2: filtering replaces short values with
  # "[FILTERED]", so params just under the limit can grow past it.
  it "keeps params within 64,000 bytes after filtering made them longer" do
    RailsErrorDashboard.configuration.filter_sensitive_data = true
    pins = (1..300).to_h { |i| [ "pin#{i}", "1" ] }
    room = 63_990 - { "blob" => "" }.merge(pins).to_json.bytesize
    params = { "blob" => "x" * room }.merge(pins).to_json

    RailsErrorDashboard::Commands::LogError.call(boom("params grew"), request_params: params)

    stored = logs.sole.request_params
    expect(stored.bytesize).to be <= 64_000
    expect(JSON.parse(stored)).to include("pin1" => "[FILTERED]", "_truncated" => true)
  end

  # capture-hardening-0-17/REQ-4: the sync extractor keeps 1,000 characters of
  # each cause's message; the async payload now does the same on the request
  # thread, before the filter runs over it.
  it "limits cause messages in the async payload as the sync path does" do
    RailsErrorDashboard.configuration.async_logging = true
    error = begin
      begin
        raise ArgumentError, "c" * 5_000
      rescue ArgumentError
        raise StandardError, "outer"
      end
    rescue StandardError => e
      e
    end

    RailsErrorDashboard::Commands::LogError.call(error)

    exception_data, = enqueued_jobs
      .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
      .fetch(:args)
    expect(exception_data["cause_chain"].first["message"].length).to eq(1_000)
  end

  # capture-hardening-0-17/REQ-3, capture-hardening-0-17/REQ-4
  it "stores the error without a context payload too big to store" do
    RailsErrorDashboard.configuration.enable_local_variables = true
    locals = { "payload" => { type: "String", value: "v" * 70_000 } }

    RailsErrorDashboard::Commands::LogError.call(boom("locals too big"), _serialized_local_variables: locals)

    row = logs.sole
    expect(row.message).to eq("locals too big")
    expect(row.local_variables).to be_nil
  end
end
