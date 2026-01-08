# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Configuration do
  subject(:config) { described_class.new }

  describe "initialization" do
    describe "existing configuration defaults" do
      it { expect(config.dashboard_username).to eq("gandalf") }
      it { expect(config.dashboard_password).to eq("youshallnotpass") }
      it { expect(config.user_model).to eq("User") }
      it { expect(config.retention_days).to eq(90) }
      it { expect(config.enable_middleware).to be true }
      it { expect(config.enable_error_subscriber).to be true }
    end

    describe "Phase 1: new configuration defaults" do
      it "sets custom_severity_rules to empty hash" do
        expect(config.custom_severity_rules).to eq({})
      end

      it "sets ignored_exceptions to empty array" do
        expect(config.ignored_exceptions).to eq([])
      end

      it "sets sampling_rate to 1.0 (100%)" do
        expect(config.sampling_rate).to eq(1.0)
      end

      it "sets async_logging to false" do
        expect(config.async_logging).to be false
      end

      it "sets async_adapter to :sidekiq" do
        expect(config.async_adapter).to eq(:sidekiq)
      end

      it "sets max_backtrace_lines to 50" do
        expect(config.max_backtrace_lines).to eq(50)
      end

      it "initializes notification_callbacks hash" do
        expect(config.notification_callbacks).to be_a(Hash)
        expect(config.notification_callbacks.keys).to contain_exactly(
          :error_logged,
          :critical_error,
          :error_resolved
        )
      end

      it "initializes each callback array" do
        expect(config.notification_callbacks[:error_logged]).to eq([])
        expect(config.notification_callbacks[:critical_error]).to eq([])
        expect(config.notification_callbacks[:error_resolved]).to eq([])
      end
    end

    describe "Phase 4.3: baseline alert configuration defaults" do
      it "sets enable_baseline_alerts to false (opt-in)" do
        expect(config.enable_baseline_alerts).to be false
      end

      it "sets baseline_alert_threshold_std_devs to 2.0" do
        expect(config.baseline_alert_threshold_std_devs).to eq(2.0)
      end

      it "sets baseline_alert_severities to [:critical, :high]" do
        expect(config.baseline_alert_severities).to eq([ :critical, :high ])
      end

      it "sets baseline_alert_cooldown_minutes to 120" do
        expect(config.baseline_alert_cooldown_minutes).to eq(120)
      end
    end
  end

  describe "#reset!" do
    it "resets all configuration to defaults" do
      config.sampling_rate = 0.5
      config.async_logging = true
      config.custom_severity_rules = { "CustomError" => :critical }
      config.ignored_exceptions = [ "TestError" ]

      config.reset!

      expect(config.sampling_rate).to eq(1.0)
      expect(config.async_logging).to be false
      expect(config.custom_severity_rules).to eq({})
      expect(config.ignored_exceptions).to eq([])
    end

    it "resets notification callbacks" do
      config.notification_callbacks[:error_logged] << ->(_) { }

      config.reset!

      expect(config.notification_callbacks[:error_logged]).to eq([])
    end
  end

  describe "attribute accessors" do
    describe "custom_severity_rules" do
      it "can be set to a hash" do
        rules = { "PaymentError" => :critical, "ValidationError" => :low }
        config.custom_severity_rules = rules

        expect(config.custom_severity_rules).to eq(rules)
      end
    end

    describe "ignored_exceptions" do
      it "can be set to an array" do
        ignored = [ "ActionController::RoutingError", /Custom.*Error/ ]
        config.ignored_exceptions = ignored

        expect(config.ignored_exceptions).to eq(ignored)
      end
    end

    describe "sampling_rate" do
      it "can be set to a float between 0 and 1" do
        config.sampling_rate = 0.25

        expect(config.sampling_rate).to eq(0.25)
      end
    end

    describe "async_logging" do
      it "can be set to true" do
        config.async_logging = true

        expect(config.async_logging).to be true
      end

      it "can be set to false" do
        config.async_logging = false

        expect(config.async_logging).to be false
      end
    end

    describe "async_adapter" do
      it "can be set to :sidekiq" do
        config.async_adapter = :sidekiq

        expect(config.async_adapter).to eq(:sidekiq)
      end

      it "can be set to :solid_queue" do
        config.async_adapter = :solid_queue

        expect(config.async_adapter).to eq(:solid_queue)
      end

      it "can be set to :async" do
        config.async_adapter = :async

        expect(config.async_adapter).to eq(:async)
      end
    end

    describe "max_backtrace_lines" do
      it "can be set to an integer" do
        config.max_backtrace_lines = 100

        expect(config.max_backtrace_lines).to eq(100)
      end
    end

    describe "Phase 4.3: baseline alert attributes" do
      describe "enable_baseline_alerts" do
        it "can be set to true" do
          config.enable_baseline_alerts = true
          expect(config.enable_baseline_alerts).to be true
        end

        it "can be set to false" do
          config.enable_baseline_alerts = false
          expect(config.enable_baseline_alerts).to be false
        end
      end

      describe "baseline_alert_threshold_std_devs" do
        it "can be set to a float" do
          config.baseline_alert_threshold_std_devs = 3.5
          expect(config.baseline_alert_threshold_std_devs).to eq(3.5)
        end

        it "can be set to an integer" do
          config.baseline_alert_threshold_std_devs = 2
          expect(config.baseline_alert_threshold_std_devs).to eq(2)
        end
      end

      describe "baseline_alert_severities" do
        it "can be set to an array of symbols" do
          config.baseline_alert_severities = [ :critical ]
          expect(config.baseline_alert_severities).to eq([ :critical ])
        end

        it "can be set to multiple severities" do
          config.baseline_alert_severities = [ :critical, :high, :elevated ]
          expect(config.baseline_alert_severities).to eq([ :critical, :high, :elevated ])
        end
      end

      describe "baseline_alert_cooldown_minutes" do
        it "can be set to an integer" do
          config.baseline_alert_cooldown_minutes = 60
          expect(config.baseline_alert_cooldown_minutes).to eq(60)
        end
      end
    end
  end

  describe "notification_callbacks" do
    it "is read-only (no setter)" do
      expect(config).not_to respond_to(:notification_callbacks=)
    end

    it "provides a reader" do
      expect(config).to respond_to(:notification_callbacks)
    end
  end
end
