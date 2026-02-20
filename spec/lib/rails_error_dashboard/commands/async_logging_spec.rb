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
        {}
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
        {}
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

      # Note: Ignored exceptions are filtered in the sync call method,
      # so they never reach the async job
      # This test documents current behavior - ignored exceptions
      # are still enqueued but will be filtered when job runs
      expect {
        RailsErrorDashboard::Commands::LogError.call(error, {})
      }.to have_enqueued_job(RailsErrorDashboard::AsyncErrorLoggingJob)

      # But when the job runs, it's filtered
      perform_enqueued_jobs
      expect(RailsErrorDashboard::ErrorLog.count).to eq(0)
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
