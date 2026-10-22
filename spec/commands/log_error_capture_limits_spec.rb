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
      RailsErrorDashboard::Commands::LogError.call(boom(long_message))

      exception_data, = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args)
      expect(exception_data["message"].length).to eq(10_000 + marker_for(long_message).length)

      perform_enqueued_jobs
      expect(logs.sole.message).to eq(long_message[0, 10_000] + marker_for(long_message))
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
