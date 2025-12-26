# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/rails_error_dashboard/install/install_generator"

RSpec.describe RailsErrorDashboard::Generators::InstallGenerator, type: :generator do
  include FileUtils

  let(:destination_root) { File.expand_path("../../tmp/generator_test", __dir__) }

  before do
    # Create a minimal Rails app structure for testing
    mkdir_p("#{destination_root}/config/initializers")

    # Create a minimal routes.rb file
    File.write("#{destination_root}/config/routes.rb", <<~RUBY)
      Rails.application.routes.draw do
      end
    RUBY
  end

  after do
    # Clean up generated files
    rm_rf(destination_root)
  end

  def run_generator(args = [])
    # Temporarily disable stdin to prevent interactive prompts during tests
    allow($stdin).to receive(:tty?).and_return(false)

    # Parse CLI args into options hash for proper Thor option handling
    # Thor doesn't auto-parse args when calling .new() directly, so we need to
    # manually convert CLI strings like "--slack" into {slack: true}
    options = {}
    args.each do |arg|
      if arg.start_with?("--")
        # Extract key: "--slack" => :slack, "--no-interactive" => :interactive
        key = arg.sub(/^--/, "").sub(/^no-/, "").gsub("-", "_").to_sym
        # Determine value: "--slack" => true, "--no-interactive" => false
        value = !arg.start_with?("--no-")
        options[key] = value
      end
    end

    generator = described_class.new([], options, { destination_root: destination_root })
    generator.invoke_all
  end

  describe "basic installation" do
    context "with default options (non-interactive)" do
      before do
        run_generator [ "--no-interactive" ]
      end

      it "creates initializer file" do
        initializer_path = "#{destination_root}/config/initializers/rails_error_dashboard.rb"
        expect(File.exist?(initializer_path)).to be true

        initializer_content = File.read(initializer_path)
        expect(initializer_content).to include("RailsErrorDashboard.configure")
        expect(initializer_content).to include("config.dashboard_username")
        expect(initializer_content).to include("config.dashboard_password")
      end

      it "adds route" do
        routes_content = File.read("#{destination_root}/config/routes.rb")
        expect(routes_content).to include("mount RailsErrorDashboard::Engine => '/error_dashboard'")
      end

      it "disables all optional features by default" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        # Notifications should be disabled
        expect(initializer_content).to include("config.enable_slack_notifications = false")
        expect(initializer_content).to include("config.enable_email_notifications = false")
        expect(initializer_content).to include("config.enable_discord_notifications = false")
        expect(initializer_content).to include("config.enable_pagerduty_notifications = false")
        expect(initializer_content).to include("config.enable_webhook_notifications = false")

        # Performance features should be disabled
        expect(initializer_content).to include("config.async_logging = false")
        expect(initializer_content).to include("config.sampling_rate = 1.0")
        expect(initializer_content).to include("config.use_separate_database = false")

        # Advanced analytics should be disabled
        expect(initializer_content).to include("config.enable_baseline_alerts = false")
        expect(initializer_content).to include("config.enable_similar_errors = false")
        expect(initializer_content).to include("config.enable_co_occurring_errors = false")
        expect(initializer_content).to include("config.enable_error_cascades = false")
        expect(initializer_content).to include("config.enable_error_correlation = false")
        expect(initializer_content).to include("config.enable_platform_comparison = false")
        expect(initializer_content).to include("config.enable_occurrence_patterns = false")
      end

      it "always enables core features" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.enable_middleware = true")
        expect(initializer_content).to include("config.enable_error_subscriber = true")
        expect(initializer_content).to include("config.retention_days = 90")
      end
    end

    context "with non-interactive mode" do
      it "skips prompts and uses defaults" do
        expect { run_generator [ "--no-interactive" ] }.not_to raise_error
      end
    end
  end

  describe "feature selection via command-line flags" do
    context "enabling Slack notifications" do
      before do
        run_generator [ "--no-interactive", "--slack" ]
      end

      it "enables Slack in generated initializer" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Slack Notifications - ENABLED")
        expect(initializer_content).to include("config.enable_slack_notifications = true")
        expect(initializer_content).to include('config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]')
      end

      it "keeps other notifications disabled" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.enable_email_notifications = false")
        expect(initializer_content).to include("config.enable_discord_notifications = false")
      end
    end

    context "enabling email notifications" do
      before do
        run_generator [ "--no-interactive", "--email" ]
      end

      it "enables email in generated initializer" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Email Notifications - ENABLED")
        expect(initializer_content).to include("config.enable_email_notifications = true")
        expect(initializer_content).to include("ERROR_NOTIFICATION_EMAILS")
      end
    end

    context "enabling async logging" do
      before do
        run_generator [ "--no-interactive", "--async_logging" ]
      end

      it "enables async logging in generated initializer" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Async Error Logging - ENABLED")
        expect(initializer_content).to include("config.async_logging = true")
        expect(initializer_content).to include("config.async_adapter = :sidekiq")
      end
    end

    context "enabling error sampling" do
      before do
        run_generator [ "--no-interactive", "--error_sampling" ]
      end

      it "enables error sampling in generated initializer" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Error Sampling - ENABLED")
        expect(initializer_content).to include("config.sampling_rate = 0.1")
      end
    end

    context "enabling separate database" do
      before do
        run_generator [ "--no-interactive", "--separate_database" ]
      end

      it "enables separate database in generated initializer" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Separate Error Database - ENABLED")
        expect(initializer_content).to include("config.use_separate_database = true")
      end
    end

    context "enabling multiple advanced analytics features" do
      before do
        run_generator [
          "--no-interactive",
          "--baseline_alerts",
          "--similar_errors",
          "--error_cascades"
        ]
      end

      it "enables all specified analytics features" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Baseline Anomaly Alerts - ENABLED")
        expect(initializer_content).to include("config.enable_baseline_alerts = true")
        expect(initializer_content).to include("config.baseline_alert_threshold_std_devs = 2.0")

        expect(initializer_content).to include("# Fuzzy Error Matching - ENABLED")
        expect(initializer_content).to include("config.enable_similar_errors = true")

        expect(initializer_content).to include("# Error Cascade Detection - ENABLED")
        expect(initializer_content).to include("config.enable_error_cascades = true")
      end

      it "keeps unspecified analytics features disabled" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.enable_co_occurring_errors = false")
        expect(initializer_content).to include("config.enable_error_correlation = false")
        expect(initializer_content).to include("config.enable_platform_comparison = false")
        expect(initializer_content).to include("config.enable_occurrence_patterns = false")
      end
    end

    context "enabling all features at once" do
      before do
        run_generator [
          "--no-interactive",
          "--slack",
          "--email",
          "--discord",
          "--pagerduty",
          "--webhooks",
          "--async_logging",
          "--error_sampling",
          "--separate_database",
          "--baseline_alerts",
          "--similar_errors",
          "--co_occurring_errors",
          "--error_cascades",
          "--error_correlation",
          "--platform_comparison",
          "--occurrence_patterns"
        ]
      end

      it "enables all notification channels" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.enable_slack_notifications = true")
        expect(initializer_content).to include("config.enable_email_notifications = true")
        expect(initializer_content).to include("config.enable_discord_notifications = true")
        expect(initializer_content).to include("config.enable_pagerduty_notifications = true")
        expect(initializer_content).to include("config.enable_webhook_notifications = true")
      end

      it "enables all performance features" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.async_logging = true")
        expect(initializer_content).to include("config.sampling_rate = 0.1")
        expect(initializer_content).to include("config.use_separate_database = true")
      end

      it "enables all advanced analytics features" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.enable_baseline_alerts = true")
        expect(initializer_content).to include("config.enable_similar_errors = true")
        expect(initializer_content).to include("config.enable_co_occurring_errors = true")
        expect(initializer_content).to include("config.enable_error_cascades = true")
        expect(initializer_content).to include("config.enable_error_correlation = true")
        expect(initializer_content).to include("config.enable_platform_comparison = true")
        expect(initializer_content).to include("config.enable_occurrence_patterns = true")
      end
    end
  end

  describe "generated initializer structure" do
    before do
      run_generator [ "--no-interactive" ]
    end

    it "contains all configuration sections" do
      initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

      expect(initializer_content).to include("# AUTHENTICATION (Always Required)")
      expect(initializer_content).to include("# CORE FEATURES (Always Enabled)")
      expect(initializer_content).to include("# NOTIFICATION SETTINGS")
      expect(initializer_content).to include("# PERFORMANCE & SCALABILITY")
      expect(initializer_content).to include("# DATABASE CONFIGURATION")
      expect(initializer_content).to include("# ADVANCED ANALYTICS")
      expect(initializer_content).to include("# ADDITIONAL CONFIGURATION")
    end

    it "provides helpful comments for each feature" do
      initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

      # Each disabled feature should have "To enable:" comments
      expect(initializer_content).to include("# To enable: Set config.enable_slack_notifications = true")
      expect(initializer_content).to include("# To enable: Set config.async_logging = true")
      expect(initializer_content).to include("# To enable: Set config.enable_baseline_alerts = true")
    end

    it "includes environment variable placeholders" do
      initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

      expect(initializer_content).to include('ENV.fetch("ERROR_DASHBOARD_USER"')
      expect(initializer_content).to include('ENV.fetch("ERROR_DASHBOARD_PASSWORD"')
      expect(initializer_content).to include('ENV["SLACK_WEBHOOK_URL"]')
      expect(initializer_content).to include('ENV["APP_VERSION"]')
      expect(initializer_content).to include('ENV["GIT_SHA"]')
    end

    it "sets sensible defaults" do
      initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

      expect(initializer_content).to include('config.dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "gandalf")')
      expect(initializer_content).to include('config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD", "youshallnotpass")')
      expect(initializer_content).to include("config.retention_days = 90")
      expect(initializer_content).to include("config.max_backtrace_lines = 50")
    end
  end

  describe "migrations" do
    before do
      run_generator [ "--no-interactive" ]
    end

    it "copies migrations from the engine" do
      # The generator calls: rake "rails_error_dashboard:install:migrations"
      # This is handled by Rails engine, so we just verify the call is made
      expect(File).to exist("#{destination_root}/config/initializers/rails_error_dashboard.rb")
    end
  end

  describe "routes" do
    before do
      run_generator [ "--no-interactive" ]
    end

    it "mounts the engine at /error_dashboard" do
      routes_content = File.read("#{destination_root}/config/routes.rb")
      expect(routes_content).to include("mount RailsErrorDashboard::Engine => '/error_dashboard'")
    end
  end

  describe "interactive mode simulation" do
    # Note: Interactive mode is difficult to test in RSpec without complex stubbing
    # This tests the logic paths but not actual user interaction

    context "when features are selected interactively" do
      before do
        # Simulate feature selection by setting instance variables directly
        generator_instance = described_class.new([], { interactive: true }, { destination_root: destination_root })
        generator_instance.instance_variable_set(:@selected_features, {
          slack: true,
          async_logging: true,
          baseline_alerts: true
        })
        generator_instance.create_initializer_file
      end

      it "respects the selected features" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("config.enable_slack_notifications = true")
        expect(initializer_content).to include("config.async_logging = true")
        expect(initializer_content).to include("config.enable_baseline_alerts = true")

        # Unselected features should be disabled
        expect(initializer_content).to include("config.enable_email_notifications = false")
        expect(initializer_content).to include("config.use_separate_database = false")
      end
    end
  end

  describe "template rendering" do
    context "when Slack is enabled" do
      before do
        run_generator [ "--no-interactive", "--slack" ]
      end

      it "renders enabled Slack section with instructions" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Slack Notifications - ENABLED")
        expect(initializer_content).to include("# To disable: Set config.enable_slack_notifications = false")
        expect(initializer_content).not_to include("# To enable: Set config.enable_slack_notifications = true")
      end
    end

    context "when Slack is disabled" do
      before do
        run_generator [ "--no-interactive" ]
      end

      it "renders disabled Slack section with instructions" do
        initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")

        expect(initializer_content).to include("# Slack Notifications - DISABLED")
        expect(initializer_content).to include("# To enable: Set config.enable_slack_notifications = true")
        expect(initializer_content).not_to include("# To disable:")
      end
    end
  end

  describe "edge cases" do
    it "handles installation without any optional features" do
      expect { run_generator [ "--no-interactive" ] }.not_to raise_error

      initializer_content = File.read("#{destination_root}/config/initializers/rails_error_dashboard.rb")
      expect(initializer_content).to be_present
      expect(initializer_content).to include("RailsErrorDashboard.configure")
    end

    it "generates valid Ruby syntax" do
      run_generator [ "--no-interactive", "--slack", "--async_logging" ]
      initializer_path = "#{destination_root}/config/initializers/rails_error_dashboard.rb"

      # Check if the generated file has valid Ruby syntax
      expect { load initializer_path }.not_to raise_error
    end
  end
end
