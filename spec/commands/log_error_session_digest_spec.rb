# frozen_string_literal: true

require "rails_helper"
require "rake"

# A session ID is a bearer credential: whoever reads it from the occurrences
# table (or from a queue's backing store) can replay it. The only consumer is
# an equality scope, so a keyed digest keeps "these occurrences were one
# session" without keeping the credential.
RSpec.describe "session ID digest" do
  let(:filter) { RailsErrorDashboard::Services::SensitiveDataFilter }
  let(:occurrences) { RailsErrorDashboard::ErrorOccurrence }
  let(:raw) { "a" * 32 }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.sampling_rate = 1.0
    config.filter_sensitive_data = true
    config.enable_storm_protection = false
    config.async_logging = false
    filter.reset!
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    filter.reset!
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
  end

  def boom
    error = StandardError.new("session digest #{SecureRandom.hex(4)}")
    error.set_backtrace([ "#{Rails.root}/app/models/audit.rb:12:in 'run'" ])
    error
  end

  describe "SensitiveDataFilter.digest_session_id" do
    it "returns h1: plus 32 hex characters and never the raw value" do
      digest = filter.digest_session_id(raw)

      expect(digest).to match(/\Ah1:\h{32}\z/)
      expect(digest).not_to include(raw)
    end

    it "is stable for one value and different for another" do
      expect(filter.digest_session_id(raw)).to eq(filter.digest_session_id(raw))
      expect(filter.digest_session_id(raw)).not_to eq(filter.digest_session_id("b" * 32))
    end

    it "is keyed: an unkeyed SHA-256 of the ID does not reproduce it" do
      expect(filter.digest_session_id(raw)).not_to include(Digest::SHA256.hexdigest(raw)[0, 32])
    end

    it "returns nil for nil and blank" do
      expect(filter.digest_session_id(nil)).to be_nil
      expect(filter.digest_session_id("")).to be_nil
    end

    it "returns an existing digest unchanged" do
      digest = filter.digest_session_id(raw)

      expect(filter.digest_session_id(digest)).to eq(digest)
    end

    it "accepts a Rack session ID object" do
      rack_id = Rack::Session::SessionId.new(raw)

      expect(filter.digest_session_id(rack_id)).to eq(filter.digest_session_id(raw))
    end

    it "falls back to a fixed key rather than raising when secret_key_base is blank" do
      allow(Rails.application).to receive(:secret_key_base).and_return(nil)

      expect(filter.digest_session_id(raw)).to match(/\Ah1:\h{32}\z/)
    end

    it "returns nil rather than raising, and never the raw value, when hashing fails" do
      allow(OpenSSL::HMAC).to receive(:hexdigest).and_raise(RuntimeError, "boom")

      expect(filter.digest_session_id(raw)).to be_nil
    end
  end

  describe "sync capture" do
    it "stores the digest, not the raw ID" do
      RailsErrorDashboard::Commands::LogError.call(boom, session_id: raw)

      stored = occurrences.last.session_id
      expect(stored).to match(/\Ah1:\h{32}\z/)
      expect(stored).not_to include(raw)
    end

    it "stores the raw ID when filter_sensitive_data is off (the operator's choice)" do
      RailsErrorDashboard.configuration.filter_sensitive_data = false

      RailsErrorDashboard::Commands::LogError.call(boom, session_id: raw)

      expect(occurrences.last.session_id).to eq(raw)
    end

    it "stores nil when there is no session" do
      RailsErrorDashboard::Commands::LogError.call(boom)

      expect(occurrences.last.session_id).to be_nil
    end
  end

  describe "async capture" do
    before { RailsErrorDashboard.configuration.async_logging = true }

    it "does not carry the raw ID across the queue" do
      RailsErrorDashboard::Commands::LogError.call(boom, session_id: raw)

      payload = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args).to_json

      expect(payload).not_to include(raw)
      expect(payload).to match(/h1:\h{32}/)
    end

    it "stores the same digest the sync path would" do
      RailsErrorDashboard::Commands::LogError.call(boom, session_id: raw)
      perform_enqueued_jobs

      expect(occurrences.last.session_id).to eq(filter.digest_session_id(raw))
    end
  end

  describe "ErrorOccurrence.for_session" do
    let(:error_log) { create(:error_log) }

    it "finds a digested row from the raw ID" do
      row = create(:error_occurrence, error_log: error_log, session_id: filter.digest_session_id(raw))

      expect(occurrences.for_session(raw)).to contain_exactly(row)
    end

    it "finds a digested row from the digest itself" do
      row = create(:error_occurrence, error_log: error_log, session_id: filter.digest_session_id(raw))

      expect(occurrences.for_session(filter.digest_session_id(raw))).to contain_exactly(row)
    end

    it "still finds a row stored raw before the upgrade" do
      legacy = create(:error_occurrence, error_log: error_log, session_id: raw)

      expect(occurrences.for_session(raw)).to contain_exactly(legacy)
    end

    it "returns nothing for nil rather than every session-less row" do
      create(:error_occurrence, error_log: error_log, session_id: nil)

      expect(occurrences.for_session(nil)).to be_empty
    end
  end

  describe "rake error_dashboard:digest_session_ids" do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("error_dashboard:digest_session_ids") }

    let(:task) { Rake::Task["error_dashboard:digest_session_ids"] }
    let(:error_log) { create(:error_log) }

    before { task.reenable }

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end

    it "digests raw rows, leaves digested and nil rows alone, and is idempotent" do
      legacy = create(:error_occurrence, error_log: error_log, session_id: raw)
      done = create(:error_occurrence, error_log: error_log, session_id: filter.digest_session_id("b" * 32))
      blank = create(:error_occurrence, error_log: error_log, session_id: nil)

      first = capture_stdout { task.invoke }

      expect(legacy.reload.session_id).to eq(filter.digest_session_id(raw))
      expect(done.reload.session_id).to eq(filter.digest_session_id("b" * 32))
      expect(blank.reload.session_id).to be_nil
      expect(first).to include("Session IDs digested: 1")

      task.reenable
      second = capture_stdout { task.invoke }

      expect(legacy.reload.session_id).to eq(filter.digest_session_id(raw))
      expect(second).to include("Session IDs digested: 0")
    end
  end
end
