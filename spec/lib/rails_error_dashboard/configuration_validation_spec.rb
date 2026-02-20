# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Configuration, "#validate!" do
  let(:config) { described_class.new }

  describe "valid configuration" do
    it "passes validation with default values" do
      expect { config.validate! }.not_to raise_error
    end

    it "returns true when valid" do
      expect(config.validate!).to be true
    end
  end

  describe "sampling_rate validation" do
    it "accepts 0.0 (0%)" do
      config.sampling_rate = 0.0
      expect { config.validate! }.not_to raise_error
    end

    it "accepts 1.0 (100%)" do
      config.sampling_rate = 1.0
      expect { config.validate! }.not_to raise_error
    end

    it "accepts 0.5 (50%)" do
      config.sampling_rate = 0.5
      expect { config.validate! }.not_to raise_error
    end

    it "rejects negative values" do
      config.sampling_rate = -0.1
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /sampling_rate must be between 0.0 and 1.0.*got: -0.1/
      )
    end

    it "rejects values > 1.0" do
      config.sampling_rate = 1.5
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /sampling_rate must be between 0.0 and 1.0.*got: 1.5/
      )
    end

    it "accepts nil (uses default)" do
      config.sampling_rate = nil
      expect { config.validate! }.not_to raise_error
    end
  end

  describe "retention_days validation" do
    it "accepts positive values" do
      config.retention_days = 30
      expect { config.validate! }.not_to raise_error
    end

    it "accepts 1 (minimum)" do
      config.retention_days = 1
      expect { config.validate! }.not_to raise_error
    end

    it "rejects 0" do
      config.retention_days = 0
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /retention_days must be at least 1 day.*got: 0/
      )
    end

    it "rejects negative values" do
      config.retention_days = -10
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /retention_days must be at least 1 day.*got: -10/
      )
    end
  end

  describe "max_backtrace_lines validation" do
    it "accepts positive values" do
      config.max_backtrace_lines = 100
      expect { config.validate! }.not_to raise_error
    end

    it "accepts 1 (minimum)" do
      config.max_backtrace_lines = 1
      expect { config.validate! }.not_to raise_error
    end

    it "rejects 0" do
      config.max_backtrace_lines = 0
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /max_backtrace_lines must be at least 1.*got: 0/
      )
    end

    it "rejects negative values" do
      config.max_backtrace_lines = -5
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /max_backtrace_lines must be at least 1.*got: -5/
      )
    end
  end

  describe "rate_limit_per_minute validation" do
    context "when rate limiting is disabled" do
      it "does not validate rate_limit_per_minute" do
        config.enable_rate_limiting = false
        config.rate_limit_per_minute = -1
        expect { config.validate! }.not_to raise_error
      end
    end

    context "when rate limiting is enabled" do
      before { config.enable_rate_limiting = true }

      it "accepts positive values" do
        config.rate_limit_per_minute = 100
        expect { config.validate! }.not_to raise_error
      end

      it "accepts 1 (minimum)" do
        config.rate_limit_per_minute = 1
        expect { config.validate! }.not_to raise_error
      end

      it "rejects 0" do
        config.rate_limit_per_minute = 0
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /rate_limit_per_minute must be at least 1.*got: 0/
        )
      end

      it "rejects negative values" do
        config.rate_limit_per_minute = -10
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /rate_limit_per_minute must be at least 1.*got: -10/
        )
      end
    end
  end

  describe "baseline alert validation" do
    context "when baseline alerts are disabled" do
      it "does not validate baseline alert settings" do
        config.enable_baseline_alerts = false
        config.baseline_alert_threshold_std_devs = -1
        config.baseline_alert_cooldown_minutes = -1
        config.baseline_alert_severities = [ :invalid ]
        expect { config.validate! }.not_to raise_error
      end
    end

    context "when baseline alerts are enabled" do
      before { config.enable_baseline_alerts = true }

      describe "baseline_alert_threshold_std_devs" do
        it "accepts positive values" do
          config.baseline_alert_threshold_std_devs = 2.5
          expect { config.validate! }.not_to raise_error
        end

        it "rejects 0" do
          config.baseline_alert_threshold_std_devs = 0
          expect { config.validate! }.to raise_error(
            RailsErrorDashboard::ConfigurationError,
            /baseline_alert_threshold_std_devs must be positive.*got: 0/
          )
        end

        it "rejects negative values" do
          config.baseline_alert_threshold_std_devs = -1.5
          expect { config.validate! }.to raise_error(
            RailsErrorDashboard::ConfigurationError,
            /baseline_alert_threshold_std_devs must be positive.*got: -1.5/
          )
        end
      end

      describe "baseline_alert_cooldown_minutes" do
        it "accepts positive values" do
          config.baseline_alert_cooldown_minutes = 60
          expect { config.validate! }.not_to raise_error
        end

        it "accepts 1 (minimum)" do
          config.baseline_alert_cooldown_minutes = 1
          expect { config.validate! }.not_to raise_error
        end

        it "rejects 0" do
          config.baseline_alert_cooldown_minutes = 0
          expect { config.validate! }.to raise_error(
            RailsErrorDashboard::ConfigurationError,
            /baseline_alert_cooldown_minutes must be at least 1.*got: 0/
          )
        end

        it "rejects negative values" do
          config.baseline_alert_cooldown_minutes = -30
          expect { config.validate! }.to raise_error(
            RailsErrorDashboard::ConfigurationError,
            /baseline_alert_cooldown_minutes must be at least 1.*got: -30/
          )
        end
      end

      describe "baseline_alert_severities" do
        it "accepts valid severities" do
          config.baseline_alert_severities = [ :critical, :high ]
          expect { config.validate! }.not_to raise_error
        end

        it "accepts all valid severities" do
          config.baseline_alert_severities = [ :critical, :high, :medium, :low ]
          expect { config.validate! }.not_to raise_error
        end

        it "rejects invalid severities" do
          config.baseline_alert_severities = [ :critical, :invalid, :bad ]
          expect { config.validate! }.to raise_error(
            RailsErrorDashboard::ConfigurationError,
            /baseline_alert_severities contains invalid values.*\[:invalid, :bad\]/
          )
        end
      end
    end
  end

  describe "async_adapter validation" do
    context "when async logging is disabled" do
      it "does not validate async_adapter" do
        config.async_logging = false
        config.async_adapter = :invalid
        expect { config.validate! }.not_to raise_error
      end
    end

    context "when async logging is enabled" do
      before { config.async_logging = true }

      it "accepts :sidekiq" do
        config.async_adapter = :sidekiq
        expect { config.validate! }.not_to raise_error
      end

      it "accepts :solid_queue" do
        config.async_adapter = :solid_queue
        expect { config.validate! }.not_to raise_error
      end

      it "accepts :async" do
        config.async_adapter = :async
        expect { config.validate! }.not_to raise_error
      end

      it "rejects invalid adapters" do
        config.async_adapter = :resque
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /async_adapter must be one of.*got: :resque/
        )
      end
    end
  end

  describe "notification validation" do
    describe "Slack notifications" do
      it "requires webhook URL when enabled" do
        config.enable_slack_notifications = true
        config.slack_webhook_url = nil
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /slack_webhook_url is required when enable_slack_notifications is true/
        )
      end

      it "rejects empty webhook URL" do
        config.enable_slack_notifications = true
        config.slack_webhook_url = "   "
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /slack_webhook_url is required/
        )
      end

      it "accepts valid webhook URL" do
        config.enable_slack_notifications = true
        config.slack_webhook_url = "https://hooks.slack.com/services/..."
        expect { config.validate! }.not_to raise_error
      end

      it "does not validate when disabled" do
        config.enable_slack_notifications = false
        config.slack_webhook_url = nil
        expect { config.validate! }.not_to raise_error
      end
    end

    describe "Email notifications" do
      it "requires recipients when enabled" do
        config.enable_email_notifications = true
        config.notification_email_recipients = []
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /notification_email_recipients is required when enable_email_notifications is true/
        )
      end

      it "accepts valid recipients" do
        config.enable_email_notifications = true
        config.notification_email_recipients = [ "admin@example.com" ]
        expect { config.validate! }.not_to raise_error
      end

      it "does not validate when disabled" do
        config.enable_email_notifications = false
        config.notification_email_recipients = []
        expect { config.validate! }.not_to raise_error
      end
    end

    describe "Discord notifications" do
      it "requires webhook URL when enabled" do
        config.enable_discord_notifications = true
        config.discord_webhook_url = nil
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /discord_webhook_url is required when enable_discord_notifications is true/
        )
      end

      it "rejects empty webhook URL" do
        config.enable_discord_notifications = true
        config.discord_webhook_url = "   "
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /discord_webhook_url is required/
        )
      end

      it "accepts valid webhook URL" do
        config.enable_discord_notifications = true
        config.discord_webhook_url = "https://discord.com/api/webhooks/..."
        expect { config.validate! }.not_to raise_error
      end
    end

    describe "PagerDuty notifications" do
      it "requires integration key when enabled" do
        config.enable_pagerduty_notifications = true
        config.pagerduty_integration_key = nil
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /pagerduty_integration_key is required when enable_pagerduty_notifications is true/
        )
      end

      it "rejects empty integration key" do
        config.enable_pagerduty_notifications = true
        config.pagerduty_integration_key = "   "
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /pagerduty_integration_key is required/
        )
      end

      it "accepts valid integration key" do
        config.enable_pagerduty_notifications = true
        config.pagerduty_integration_key = "abc123"
        expect { config.validate! }.not_to raise_error
      end
    end

    describe "Webhook notifications" do
      it "requires webhook URLs when enabled" do
        config.enable_webhook_notifications = true
        config.webhook_urls = []
        expect { config.validate! }.to raise_error(
          RailsErrorDashboard::ConfigurationError,
          /webhook_urls is required when enable_webhook_notifications is true/
        )
      end

      it "accepts valid webhook URLs" do
        config.enable_webhook_notifications = true
        config.webhook_urls = [ "https://example.com/webhook" ]
        expect { config.validate! }.not_to raise_error
      end
    end
  end

  describe "database validation" do
    it "requires database name when separate database is enabled" do
      config.use_separate_database = true
      config.database = nil
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /database configuration is required when use_separate_database is true/
      )
    end

    it "rejects empty database name" do
      config.use_separate_database = true
      config.database = "   "
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /database configuration is required/
      )
    end

    it "accepts valid database name" do
      config.use_separate_database = true
      config.database = :error_dashboard
      expect { config.validate! }.not_to raise_error
    end

    it "does not validate when disabled" do
      config.use_separate_database = false
      config.database = nil
      expect { config.validate! }.not_to raise_error
    end
  end

  describe "log_level validation" do
    it "accepts :debug" do
      config.log_level = :debug
      expect { config.validate! }.not_to raise_error
    end

    it "accepts :info" do
      config.log_level = :info
      expect { config.validate! }.not_to raise_error
    end

    it "accepts :warn" do
      config.log_level = :warn
      expect { config.validate! }.not_to raise_error
    end

    it "accepts :error" do
      config.log_level = :error
      expect { config.validate! }.not_to raise_error
    end

    it "accepts :fatal" do
      config.log_level = :fatal
      expect { config.validate! }.not_to raise_error
    end

    it "accepts :silent" do
      config.log_level = :silent
      expect { config.validate! }.not_to raise_error
    end

    it "rejects invalid log levels" do
      config.log_level = :invalid
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /log_level must be one of.*got: :invalid/
      )
    end
  end

  describe "total_users_for_impact validation" do
    it "accepts positive values" do
      config.total_users_for_impact = 1000
      expect { config.validate! }.not_to raise_error
    end

    it "accepts 1 (minimum)" do
      config.total_users_for_impact = 1
      expect { config.validate! }.not_to raise_error
    end

    it "rejects 0" do
      config.total_users_for_impact = 0
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /total_users_for_impact must be at least 1.*got: 0/
      )
    end

    it "rejects negative values" do
      config.total_users_for_impact = -100
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /total_users_for_impact must be at least 1.*got: -100/
      )
    end

    it "accepts nil (auto-detect)" do
      config.total_users_for_impact = nil
      expect { config.validate! }.not_to raise_error
    end
  end

  describe "custom_fingerprint validation" do
    it "accepts nil (default)" do
      config.custom_fingerprint = nil
      expect { config.validate! }.not_to raise_error
    end

    it "accepts a lambda" do
      config.custom_fingerprint = ->(ex, ctx) { ex.class.name }
      expect { config.validate! }.not_to raise_error
    end

    it "accepts a proc" do
      config.custom_fingerprint = proc { |ex, ctx| ex.class.name }
      expect { config.validate! }.not_to raise_error
    end

    it "accepts any object responding to .call" do
      callable = Class.new { def call(ex, ctx) = ex.class.name }.new
      config.custom_fingerprint = callable
      expect { config.validate! }.not_to raise_error
    end

    it "rejects non-callable values" do
      config.custom_fingerprint = "not a lambda"
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /custom_fingerprint must respond to .call/
      )
    end

    it "rejects integer values" do
      config.custom_fingerprint = 42
      expect { config.validate! }.to raise_error(
        RailsErrorDashboard::ConfigurationError,
        /custom_fingerprint must respond to .call/
      )
    end
  end

  describe "multiple validation errors" do
    it "reports all errors at once" do
      config.sampling_rate = 2.0
      config.retention_days = -10
      config.max_backtrace_lines = 0

      expect { config.validate! }.to raise_error(RailsErrorDashboard::ConfigurationError) do |error|
        expect(error.message).to include("sampling_rate must be between 0.0 and 1.0")
        expect(error.message).to include("retention_days must be at least 1 day")
        expect(error.message).to include("max_backtrace_lines must be at least 1")
        expect(error.message).to include("1.")
        expect(error.message).to include("2.")
        expect(error.message).to include("3.")
      end
    end

    it "includes helpful footer message" do
      config.sampling_rate = -1

      expect { config.validate! }.to raise_error(RailsErrorDashboard::ConfigurationError) do |error|
        expect(error.message).to include("config/initializers/rails_error_dashboard.rb")
      end
    end
  end

  describe "ConfigurationError" do
    it "stores errors array" do
      error = RailsErrorDashboard::ConfigurationError.new([ "error1", "error2" ])
      expect(error.errors).to eq([ "error1", "error2" ])
    end

    it "handles single error string" do
      error = RailsErrorDashboard::ConfigurationError.new("single error")
      expect(error.errors).to eq([ "single error" ])
    end

    it "formats message with numbered list" do
      error = RailsErrorDashboard::ConfigurationError.new([ "first", "second" ])
      expect(error.message).to include("1. first")
      expect(error.message).to include("2. second")
    end
  end
end
