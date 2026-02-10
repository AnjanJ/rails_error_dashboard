# frozen_string_literal: true

module RailsErrorDashboard
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs Rails Error Dashboard and generates the necessary files"

      class_option :interactive, type: :boolean, default: true, desc: "Interactive feature selection"
      # Notification options
      class_option :slack, type: :boolean, default: false, desc: "Enable Slack notifications"
      class_option :email, type: :boolean, default: false, desc: "Enable email notifications"
      class_option :discord, type: :boolean, default: false, desc: "Enable Discord notifications"
      class_option :pagerduty, type: :boolean, default: false, desc: "Enable PagerDuty notifications"
      class_option :webhooks, type: :boolean, default: false, desc: "Enable webhook notifications"
      # Performance options
      class_option :async_logging, type: :boolean, default: false, desc: "Enable async error logging"
      class_option :error_sampling, type: :boolean, default: false, desc: "Enable error sampling (reduce volume)"
      class_option :separate_database, type: :boolean, default: false, desc: "Use separate database for errors"
      class_option :database, type: :string, default: nil, desc: "Database name to use for errors (e.g., 'error_dashboard')"
      # Advanced analytics options
      class_option :baseline_alerts, type: :boolean, default: false, desc: "Enable baseline anomaly alerts"
      class_option :similar_errors, type: :boolean, default: false, desc: "Enable fuzzy error matching"
      class_option :co_occurring_errors, type: :boolean, default: false, desc: "Enable co-occurring error detection"
      class_option :error_cascades, type: :boolean, default: false, desc: "Enable error cascade detection"
      class_option :error_correlation, type: :boolean, default: false, desc: "Enable error correlation analysis"
      class_option :platform_comparison, type: :boolean, default: false, desc: "Enable platform comparison analytics"
      class_option :occurrence_patterns, type: :boolean, default: false, desc: "Enable occurrence pattern detection"
      # Developer tools options
      class_option :source_code_integration, type: :boolean, default: false, desc: "Enable source code viewer (NEW!)"
      class_option :git_blame, type: :boolean, default: false, desc: "Enable git blame integration (NEW!)"

      def welcome_message
        say "\n"
        say "=" * 70
        say "  📊 Rails Error Dashboard Installation", :cyan
        say "=" * 70
        say "\n"
        say "Core features will be enabled automatically:", :green
        say "  ✓ Error capture (controllers, jobs, middleware)"
        say "  ✓ Dashboard UI at /error_dashboard"
        say "  ✓ Real-time updates"
        say "  ✓ Analytics & spike detection"
        say "  ✓ 90-day error retention"
        say "\n"
      end

      def select_optional_features
        return unless options[:interactive] && behavior == :invoke
        return unless $stdin.tty?  # Skip interactive mode if not running in a terminal

        say "Let's configure optional features...\n", :cyan
        say "(You can always enable/disable these later in the initializer)\n\n", :yellow

        @selected_features = {}

        # Feature definitions with descriptions - organized by category
        features = [
          # === NOTIFICATIONS ===
          {
            key: :slack,
            name: "Slack Notifications",
            description: "Send error alerts to Slack channels",
            category: "Notifications"
          },
          {
            key: :email,
            name: "Email Notifications",
            description: "Send error alerts via email",
            category: "Notifications"
          },
          {
            key: :discord,
            name: "Discord Notifications",
            description: "Send error alerts to Discord",
            category: "Notifications"
          },
          {
            key: :pagerduty,
            name: "PagerDuty Integration",
            description: "Critical errors to PagerDuty",
            category: "Notifications"
          },
          {
            key: :webhooks,
            name: "Generic Webhooks",
            description: "Send data to custom endpoints",
            category: "Notifications"
          },

          # === PERFORMANCE & SCALABILITY ===
          {
            key: :async_logging,
            name: "Async Error Logging",
            description: "Process errors in background jobs (faster responses)",
            category: "Performance"
          },
          {
            key: :error_sampling,
            name: "Error Sampling",
            description: "Log only % of non-critical errors (reduce volume)",
            category: "Performance"
          },
          {
            key: :separate_database,
            name: "Separate Error Database",
            description: "Store errors in dedicated database",
            category: "Performance"
          },

          # === ADVANCED ANALYTICS ===
          {
            key: :baseline_alerts,
            name: "Baseline Anomaly Alerts",
            description: "Auto-detect unusual error rate spikes",
            category: "Advanced Analytics"
          },
          {
            key: :similar_errors,
            name: "Fuzzy Error Matching",
            description: "Find similar errors across different hashes",
            category: "Advanced Analytics"
          },
          {
            key: :co_occurring_errors,
            name: "Co-occurring Errors",
            description: "Detect errors that happen together",
            category: "Advanced Analytics"
          },
          {
            key: :error_cascades,
            name: "Error Cascade Detection",
            description: "Identify error chains (A causes B causes C)",
            category: "Advanced Analytics"
          },
          {
            key: :error_correlation,
            name: "Error Correlation Analysis",
            description: "Correlate with versions, users, time",
            category: "Advanced Analytics"
          },
          {
            key: :platform_comparison,
            name: "Platform Comparison",
            description: "Compare iOS vs Android vs Web health",
            category: "Advanced Analytics"
          },
          {
            key: :occurrence_patterns,
            name: "Occurrence Pattern Detection",
            description: "Detect cyclical patterns and bursts",
            category: "Advanced Analytics"
          },

          # === DEVELOPER TOOLS ===
          {
            key: :source_code_integration,
            name: "Source Code Integration (NEW!)",
            description: "View source code directly in error details",
            category: "Developer Tools"
          },
          {
            key: :git_blame,
            name: "Git Blame Integration (NEW!)",
            description: "Show git blame info (author, commit, timestamp)",
            category: "Developer Tools"
          }
        ]

        features.each_with_index do |feature, index|
          say "\n[#{index + 1}/#{features.length}] #{feature[:name]}", :cyan
          say "    #{feature[:description]}", :white

          # Check if feature was passed via command line option
          if options[feature[:key]]
            @selected_features[feature[:key]] = true
            say "    ✓ Enabled (via --#{feature[:key]} flag)", :green
          else
            response = ask("    Enable? (y/N):", :yellow, limited_to: [ "y", "Y", "n", "N", "" ])
            @selected_features[feature[:key]] = response.downcase == "y"

            if @selected_features[feature[:key]]
              say "    ✓ Enabled", :green
            else
              say "    ✗ Disabled", :white
            end
          end
        end

        say "\n"
      end

      def create_initializer_file
        # Notifications
        @enable_slack = @selected_features&.dig(:slack) || options[:slack]
        @enable_email = @selected_features&.dig(:email) || options[:email]
        @enable_discord = @selected_features&.dig(:discord) || options[:discord]
        @enable_pagerduty = @selected_features&.dig(:pagerduty) || options[:pagerduty]
        @enable_webhooks = @selected_features&.dig(:webhooks) || options[:webhooks]

        # Performance
        @enable_async_logging = @selected_features&.dig(:async_logging) || options[:async_logging]
        @enable_error_sampling = @selected_features&.dig(:error_sampling) || options[:error_sampling]
        @enable_separate_database = @selected_features&.dig(:separate_database) || options[:separate_database]
        @database_name = options[:database]

        # Advanced Analytics
        @enable_baseline_alerts = @selected_features&.dig(:baseline_alerts) || options[:baseline_alerts]
        @enable_similar_errors = @selected_features&.dig(:similar_errors) || options[:similar_errors]
        @enable_co_occurring_errors = @selected_features&.dig(:co_occurring_errors) || options[:co_occurring_errors]
        @enable_error_cascades = @selected_features&.dig(:error_cascades) || options[:error_cascades]
        @enable_error_correlation = @selected_features&.dig(:error_correlation) || options[:error_correlation]
        @enable_platform_comparison = @selected_features&.dig(:platform_comparison) || options[:platform_comparison]
        @enable_occurrence_patterns = @selected_features&.dig(:occurrence_patterns) || options[:occurrence_patterns]

        # Developer Tools
        @enable_source_code_integration = @selected_features&.dig(:source_code_integration) || options[:source_code_integration]
        @enable_git_blame = @selected_features&.dig(:git_blame) || options[:git_blame]

        template "initializer.rb", "config/initializers/rails_error_dashboard.rb"
      end

      def copy_migrations
        rails_command "rails_error_dashboard:install:migrations"
      end

      def add_route
        route "mount RailsErrorDashboard::Engine => '/error_dashboard'"
      end

      def show_feature_summary
        return unless behavior == :invoke

        say "\n"
        say "=" * 70
        say "  ✓ Installation Complete!", :green
        say "=" * 70
        say "\n"

        say "Core Features (Always ON):", :cyan
        say "  ✓ Error Capture", :green
        say "  ✓ Dashboard UI", :green
        say "  ✓ Real-time Updates", :green
        say "  ✓ Analytics", :green

        # Count optional features enabled
        enabled_count = 0

        # Notifications
        notification_features = []
        notification_features << "Slack" if @enable_slack
        notification_features << "Email" if @enable_email
        notification_features << "Discord" if @enable_discord
        notification_features << "PagerDuty" if @enable_pagerduty
        notification_features << "Webhooks" if @enable_webhooks

        if notification_features.any?
          say "\nNotifications:", :cyan
          say "  ✓ #{notification_features.join(", ")}", :green
          enabled_count += notification_features.size
        end

        # Performance
        performance_features = []
        performance_features << "Async Logging" if @enable_async_logging
        performance_features << "Error Sampling" if @enable_error_sampling
        performance_features << "Separate Database" if @enable_separate_database

        if performance_features.any?
          say "\nPerformance:", :cyan
          say "  ✓ #{performance_features.join(", ")}", :green
          enabled_count += performance_features.size
        end

        # Advanced Analytics
        analytics_features = []
        analytics_features << "Baseline Alerts" if @enable_baseline_alerts
        analytics_features << "Fuzzy Matching" if @enable_similar_errors
        analytics_features << "Co-occurring Errors" if @enable_co_occurring_errors
        analytics_features << "Error Cascades" if @enable_error_cascades
        analytics_features << "Error Correlation" if @enable_error_correlation
        analytics_features << "Platform Comparison" if @enable_platform_comparison
        analytics_features << "Pattern Detection" if @enable_occurrence_patterns

        if analytics_features.any?
          say "\nAdvanced Analytics:", :cyan
          say "  ✓ #{analytics_features.join(", ")}", :green
          enabled_count += analytics_features.size
        end

        # Developer Tools
        developer_tools_features = []
        developer_tools_features << "Source Code Integration" if @enable_source_code_integration
        developer_tools_features << "Git Blame" if @enable_git_blame

        if developer_tools_features.any?
          say "\nDeveloper Tools:", :cyan
          say "  ✓ #{developer_tools_features.join(", ")}", :green
          enabled_count += developer_tools_features.size
        end

        say "\n"
        say "Configuration Required:", :yellow if enabled_count > 0
        say "  → Edit config/initializers/rails_error_dashboard.rb", :yellow if @enable_error_sampling
        say "  → Set SLACK_WEBHOOK_URL in .env", :yellow if @enable_slack
        say "  → Set ERROR_NOTIFICATION_EMAILS in .env", :yellow if @enable_email
        say "  → Set DISCORD_WEBHOOK_URL in .env", :yellow if @enable_discord
        say "  → Set PAGERDUTY_INTEGRATION_KEY in .env", :yellow if @enable_pagerduty
        say "  → Set WEBHOOK_URLS in .env", :yellow if @enable_webhooks
        say "  → Ensure Sidekiq/Solid Queue running", :yellow if @enable_async_logging
        if @enable_separate_database
          if @database_name
            say "  → Configure '#{@database_name}' database in database.yml", :yellow
          else
            say "  → Configure database in database.yml and set config.database", :yellow
          end
          say "    See docs/guides/DATABASE_OPTIONS.md for details", :yellow
        end

        say "\n"
        say "Next Steps:", :cyan
        say "  1. Run: rails db:migrate"
        say "  2. Update credentials in config/initializers/rails_error_dashboard.rb"
        say "  3. Restart your Rails server"
        say "  4. Visit http://localhost:3000/error_dashboard"
        say "\n"
        say "📖 Documentation:", :white
        say "   • Quick Start: docs/QUICKSTART.md", :white
        say "   • Complete Feature Guide: docs/FEATURES.md", :white
        say "   • All Docs: docs/README.md", :white
        say "\n"
        say "⚙️  To enable/disable features later:", :white
        say "   Edit config/initializers/rails_error_dashboard.rb", :white
        say "\n"
      end

      def show_readme
        # Skip the old README display since we have the new summary
      end
    end
  end
end
