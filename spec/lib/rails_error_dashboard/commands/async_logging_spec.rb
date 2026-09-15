# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Async Error Logging", type: :integration do
  after do
    RailsErrorDashboard.reset_configuration!
  end

  describe "with async_logging disabled (default)" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = false
      end
    end

    it "logs errors synchronously" do
      error = StandardError.new("Sync error")

      # Should NOT enqueue a job
      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.not_to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)
    end

    it "creates error log immediately" do
      error = StandardError.new("Sync error")

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end
  end

  describe "with async_logging enabled" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = true
      end
    end

    it "enqueues async job instead of logging immediately" do
      error = StandardError.new("Async error")

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)
    end

    it "does not create error log immediately" do
      error = StandardError.new("Async error")

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.not_to change(RailsErrorDashboard::ErrorLog, :count)
    end

    it "serializes exception data correctly" do
      error = StandardError.new("Async error")
      error.set_backtrace([ "test.rb:1" ])

      expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later).with(
        hash_including(
          class_name: "StandardError",
          message: "Async error",
          backtrace: [ "test.rb:1" ],
          cause_chain: nil
        ),
        # _identity carries the fingerprint as an OPAQUE 16-char digest,
        # hashed from the raw message on the request thread. No message text
        # crosses the queue -- the payload above is redacted -- and the worker
        # completes the hash by adding application_id.
        hash_including(_pre_filtered: true, _identity: match(/\A[0-9a-f]{16}\z/))
      )

      RailsErrorDashboard::Commands::LogError.call(error, {})
    end

    it "serializes cause chain for async processing" do
      error = begin
        begin
          raise ArgumentError, "root cause"
        rescue
          raise StandardError, "wrapper"
        end
      rescue => e
        e
      end

      expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later).with(
        hash_including(
          class_name: "StandardError",
          message: "wrapper",
          cause_chain: [ hash_including(class_name: "ArgumentError", message: "root cause") ]
        ),
        hash_including(_pre_filtered: true)
      )

      RailsErrorDashboard::Commands::LogError.call(error, {})
    end

    it "includes context in async job" do
      error = StandardError.new("Async error")
      context = { user_id: 123, platform: "iOS" }

      expect(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later).with(
        anything,
        hash_including(user_id: 123, platform: "iOS")
      )

      RailsErrorDashboard::Commands::LogError.call(error, context)
    end

    it "works with different queue adapters" do
      # Just verify job is enqueued - the adapter handles the rest
      [ :sidekiq, :solid_queue, :async ].each do |adapter|
        RailsErrorDashboard.configure { |c| c.async_adapter = adapter }

        error = StandardError.new("Adapter test")
        expect {
          RailsErrorDashboard::Commands::LogError.call(error, {})
        }.to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)
      end
    end
  end

  describe "when the handoff to the queue fails" do
    # Regression: perform_later does not always raise. From Rails 7.2 an
    # ActiveJob::EnqueueError raised by the adapter is caught inside
    # perform_later, which returns false and sets enqueue_error on the job.
    # call_async only rescued, so on 7.2+ the capture was dropped silently:
    # nothing queued, nothing stored, and LogError.call returned that false.
    # The storm gate had always checked this; ordinary capture had not.
    before do
      RailsErrorDashboard.configure { |config| config.async_logging = true }
    end

    # No adapter swapping here. Installing a per-class adapter (or calling
    # disable_test_adapter) detaches this job from ActiveJob::Base's test
    # adapter, and ActiveJob::TestHelper#perform_enqueued_jobs only ever
    # drains ActiveJob::Base's -- so a later spec's job sits in a queue the
    # helper cannot see and never runs. Both failure shapes call_async
    # branches on are reachable by stubbing perform_later directly.
    it "falls back to synchronous capture rather than losing the error" do
      error = StandardError.new("enqueue failure")
      error.set_backtrace([ "test.rb:1" ])
      allow(RailsErrorDashboard::AsyncErrorLoggingJob)
        .to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue store down")

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

      expect(RailsErrorDashboard::ErrorLog.last.message).to eq("enqueue failure")
    end

    it "returns the persisted record, not the falsy perform_later result" do
      error = StandardError.new("enqueue failure return value")
      error.set_backtrace([ "test.rb:1" ])
      allow(RailsErrorDashboard::AsyncErrorLoggingJob)
        .to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue store down")

      result = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result).to be_persisted
    end

    it "reports the failed handoff instead of dropping it silently" do
      error = StandardError.new("enqueue failure logging")
      error.set_backtrace([ "test.rb:1" ])
      allow(RailsErrorDashboard::AsyncErrorLoggingJob)
        .to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue store down")

      expect(RailsErrorDashboard::Logger)
        .to receive(:error).with(/Async enqueue failed/).at_least(:once)

      RailsErrorDashboard::Commands::LogError.call(error, {})
    end

    it "falls back when perform_later merely returns false (no exception raised)" do
      error = StandardError.new("silent false return")
      error.set_backtrace([ "test.rb:1" ])
      allow(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later).and_return(false)

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end
  end

  describe "end-to-end async logging" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = true
        config.async_adapter = :async
      end
    end

    it "logs error when job is performed" do
      error = StandardError.new("E2E async error")
      error.set_backtrace([ "test.rb:1" ])

      # Enqueue the job
      RailsErrorDashboard::Commands::LogError.call(error, { user_id: 456 })

      # Perform enqueued jobs
      expect {
        perform_enqueued_jobs
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.error_type).to eq("StandardError")
      expect(error_log.message).to eq("E2E async error")
      expect(error_log.user_id).to eq(456)
    end

    it "preserves cause chain through async job" do
      error = begin
        begin
          raise ArgumentError, "database connection failed"
        rescue
          raise StandardError, "user lookup failed"
        end
      rescue => e
        e
      end

      RailsErrorDashboard::Commands::LogError.call(error, {})

      perform_enqueued_jobs

      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.exception_cause).to be_present

      parsed = JSON.parse(error_log.exception_cause)
      expect(parsed.length).to eq(1)
      expect(parsed[0]["class_name"]).to eq("ArgumentError")
      expect(parsed[0]["message"]).to eq("database connection failed")
    end

    it "handles critical errors asynchronously" do
      error = SecurityError.new("Critical async error")

      RailsErrorDashboard::Commands::LogError.call(error, {})

      perform_enqueued_jobs

      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.error_type).to eq("SecurityError")
      expect(error_log.critical?).to be true
    end
  end

  describe "interaction with ignored exceptions" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = true
        config.async_adapter = :async
        config.ignored_exceptions = [ "ActionController::RoutingError" ]
      end
    end

    it "does not enqueue job for ignored exceptions" do
      error = ActionController::RoutingError.new("Not found")

      # Ignored exceptions are filtered BEFORE the async branch (since storm
      # protection moved the filter to LogError.call) — no job is enqueued
      # at all, saving the queue round-trip entirely.
      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.not_to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)

      expect(RailsErrorDashboard::ErrorLog.count).to eq(0)
    end
  end

  describe "async enqueue failure fallback (issue #114)" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = true
        config.async_adapter = :async
      end
    end

    it "falls back to sync logging when perform_later fails" do
      error = StandardError.new("Redis down test")
      error.set_backtrace([ "test.rb:1" ])

      # Simulate queue adapter failure (e.g., Redis down for Sidekiq)
      allow(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later)
        .and_raise(RuntimeError, "Error connecting to Redis on 127.0.0.1:6379 (Errno::ECONNREFUSED)")

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

      error_log = RailsErrorDashboard::ErrorLog.last
      expect(error_log.error_type).to eq("StandardError")
      expect(error_log.message).to eq("Redis down test")
    end

    it "falls back to sync logging when perform_later raises any error" do
      error = StandardError.new("Enqueue failure test")
      error.set_backtrace([ "test.rb:1" ])

      allow(RailsErrorDashboard::AsyncErrorLoggingJob).to receive(:perform_later)
        .and_raise(RuntimeError, "Queue adapter unavailable")

      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end
  end

  describe "interaction with sampling" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = true
        config.async_adapter = :async
        config.sampling_rate = 0.0  # Skip all non-critical
      end
    end

    it "still applies sampling in async mode" do
      # Non-critical error with 0% sampling
      error = StandardError.new("Should be skipped")

      # Job is enqueued but error is filtered when job runs
      RailsErrorDashboard::Commands::LogError.call(error, {})
      perform_enqueued_jobs

      expect(RailsErrorDashboard::ErrorLog.count).to eq(0)
    end

    it "logs critical errors even with 0% sampling" do
      error = SecurityError.new("Critical")

      RailsErrorDashboard::Commands::LogError.call(error, {})
      perform_enqueued_jobs

      expect(RailsErrorDashboard::ErrorLog.count).to eq(1)
    end
  end
end
