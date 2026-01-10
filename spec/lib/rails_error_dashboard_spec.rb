# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard do
  # Clean up configuration after each test
  after do
    described_class.reset_configuration!
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(RailsErrorDashboard::Configuration)
    end

    it "returns the same instance on multiple calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration

      expect(config1).to be(config2)
    end

    it "initializes with defaults if not configured" do
      expect(described_class.configuration.sampling_rate).to eq(1.0)
      expect(described_class.configuration.async_logging).to be false
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      expect { |b| described_class.configure(&b) }
        .to yield_with_args(described_class.configuration)
    end

    it "allows setting configuration values" do
      described_class.configure do |config|
        config.sampling_rate = 0.5
        config.async_logging = true
      end

      expect(described_class.configuration.sampling_rate).to eq(0.5)
      expect(described_class.configuration.async_logging).to be true
    end

    it "allows setting custom severity rules" do
      described_class.configure do |config|
        config.custom_severity_rules = { "PaymentError" => :critical }
      end

      expect(described_class.configuration.custom_severity_rules).to eq({
        "PaymentError" => :critical
      })
    end

    it "allows setting ignored exceptions" do
      described_class.configure do |config|
        config.ignored_exceptions = [ "ActionController::RoutingError" ]
      end

      expect(described_class.configuration.ignored_exceptions).to eq([
        "ActionController::RoutingError"
      ])
    end

    it "allows setting multiple configuration values at once" do
      described_class.configure do |config|
        config.sampling_rate = 0.1
        config.async_logging = true
        config.async_adapter = :solid_queue
        config.max_backtrace_lines = 25
      end

      config = described_class.configuration
      expect(config.sampling_rate).to eq(0.1)
      expect(config.async_logging).to be true
      expect(config.async_adapter).to eq(:solid_queue)
      expect(config.max_backtrace_lines).to eq(25)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to default values" do
      described_class.configure do |config|
        config.sampling_rate = 0.1
        config.async_logging = true
        config.custom_severity_rules = { "Error" => :critical }
      end

      described_class.reset_configuration!

      config = described_class.configuration
      expect(config.sampling_rate).to eq(1.0)
      expect(config.async_logging).to be false
      expect(config.custom_severity_rules).to eq({})
    end

    it "creates a new Configuration instance" do
      old_config = described_class.configuration
      described_class.reset_configuration!
      new_config = described_class.configuration

      expect(new_config).not_to be(old_config)
      expect(new_config).to be_a(RailsErrorDashboard::Configuration)
    end
  end

  describe "configuration persistence across calls" do
    it "maintains configuration values across multiple accesses" do
      described_class.configure do |config|
        config.sampling_rate = 0.75
      end

      # Access configuration multiple times
      3.times do
        expect(described_class.configuration.sampling_rate).to eq(0.75)
      end
    end

    it "allows updating configuration incrementally" do
      described_class.configure do |config|
        config.sampling_rate = 0.5
      end

      described_class.configure do |config|
        config.async_logging = true
      end

      config = described_class.configuration
      expect(config.sampling_rate).to eq(0.5) # Previous value maintained
      expect(config.async_logging).to be true # New value set
    end
  end

  describe "notification callbacks" do
    after do
      described_class.reset_configuration!
    end

    describe ".on_error_logged" do
      it "registers a callback for error logging" do
        callback_called = false
        described_class.on_error_logged do |_error_log|
          callback_called = true
        end

        expect(described_class.configuration.notification_callbacks[:error_logged].size).to eq(1)
      end

      it "executes callback when error is logged" do
        logged_error = nil
        described_class.on_error_logged do |error_log|
          logged_error = error_log
        end

        error = StandardError.new("Test error")
        error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

        expect(logged_error).to eq(error_log)
        expect(logged_error.error_type).to eq("StandardError")
      end

      it "allows multiple callbacks to be registered" do
        call_count = 0
        described_class.on_error_logged { |_| call_count += 1 }
        described_class.on_error_logged { |_| call_count += 1 }

        error = StandardError.new("Test error")
        RailsErrorDashboard::Commands::LogError.call(error, {})

        expect(call_count).to eq(2)
      end

      it "does not execute callback on error recurrence (only new errors)" do
        call_count = 0
        described_class.on_error_logged { |_| call_count += 1 }

        error = StandardError.new("Same error")
        error.set_backtrace([ "test.rb:1" ])

        # First occurrence - should trigger callback
        RailsErrorDashboard::Commands::LogError.call(error, {})
        expect(call_count).to eq(1)

        # Second occurrence - should NOT trigger callback
        RailsErrorDashboard::Commands::LogError.call(error, {})
        expect(call_count).to eq(1) # Still 1, not 2
      end
    end

    describe ".on_critical_error" do
      it "registers a callback for critical errors" do
        described_class.on_critical_error do |error_log|
          # callback
        end

        expect(described_class.configuration.notification_callbacks[:critical_error].size).to eq(1)
      end

      it "executes callback when critical error is logged" do
        logged_error = nil
        described_class.on_critical_error do |error_log|
          logged_error = error_log
        end

        error = SecurityError.new("Critical security issue")
        error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

        expect(logged_error).to eq(error_log)
        expect(logged_error.error_type).to eq("SecurityError")
        expect(logged_error.critical?).to be true
      end

      it "does not execute callback for non-critical errors" do
        callback_called = false
        described_class.on_critical_error do |_error_log|
          callback_called = true
        end

        error = StandardError.new("Non-critical error")
        RailsErrorDashboard::Commands::LogError.call(error, {})

        expect(callback_called).to be false
      end

      it "executes both error_logged and critical_error callbacks for critical errors" do
        error_logged_called = false
        critical_error_called = false

        described_class.on_error_logged { |_| error_logged_called = true }
        described_class.on_critical_error { |_| critical_error_called = true }

        error = SecurityError.new("Critical")
        RailsErrorDashboard::Commands::LogError.call(error, {})

        expect(error_logged_called).to be true
        expect(critical_error_called).to be true
      end
    end

    describe ".on_error_resolved" do
      it "registers a callback for error resolution" do
        described_class.on_error_resolved do |error_log|
          # callback
        end

        expect(described_class.configuration.notification_callbacks[:error_resolved].size).to eq(1)
      end

      it "executes callback when error is resolved" do
        resolved_error = nil
        described_class.on_error_resolved do |error_log|
          resolved_error = error_log
        end

        error = StandardError.new("Test error")
        error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

        RailsErrorDashboard::Commands::ResolveError.call(error_log.id, { resolved_by_name: "Test User" })

        expect(resolved_error).to eq(error_log.reload)
        expect(resolved_error.resolved).to be true
        expect(resolved_error.resolved_by_name).to eq("Test User")
      end

      it "allows multiple callbacks to be registered" do
        call_count = 0
        described_class.on_error_resolved { |_| call_count += 1 }
        described_class.on_error_resolved { |_| call_count += 1 }

        error = StandardError.new("Test error")
        error_log = RailsErrorDashboard::Commands::LogError.call(error, {})
        RailsErrorDashboard::Commands::ResolveError.call(error_log.id)

        expect(call_count).to eq(2)
      end
    end

    describe "callback error handling" do
      before do
        # Ensure synchronous logging for callback tests
        described_class.configuration.async_logging = false
        described_class.configuration.sampling_rate = 1.0
      end

      it "continues executing other callbacks if one fails" do
        call_count = 0

        described_class.on_error_logged do |_|
          raise "First callback error"
        end

        described_class.on_error_logged do |_|
          call_count += 1
        end

        error = StandardError.new("Test error")
        # Should not raise, should log error instead
        expect {
          RailsErrorDashboard::Commands::LogError.call(error, {})
        }.not_to raise_error

        expect(call_count).to eq(1)
      end

      it "logs errors from callbacks" do
        described_class.on_error_logged do |_|
          raise "Callback error"
        end

        error = StandardError.new("Test error")

        expect(RailsErrorDashboard::Logger).to receive(:error).with(/Error in error_logged callback/)
        RailsErrorDashboard::Commands::LogError.call(error, {})
      end
    end

    describe "callback reset" do
      it "clears all callbacks when configuration is reset" do
        described_class.on_error_logged { |_| }
        described_class.on_critical_error { |_| }
        described_class.on_error_resolved { |_| }

        expect(described_class.configuration.notification_callbacks[:error_logged].size).to eq(1)
        expect(described_class.configuration.notification_callbacks[:critical_error].size).to eq(1)
        expect(described_class.configuration.notification_callbacks[:error_resolved].size).to eq(1)

        described_class.reset_configuration!

        expect(described_class.configuration.notification_callbacks[:error_logged].size).to eq(0)
        expect(described_class.configuration.notification_callbacks[:critical_error].size).to eq(0)
        expect(described_class.configuration.notification_callbacks[:error_resolved].size).to eq(0)
      end
    end
  end
end
