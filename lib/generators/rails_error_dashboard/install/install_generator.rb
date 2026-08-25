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
      class_option :async_logging, type: :boolean, default: true, desc: "Enable async error logging (default: true, uses Rails :async adapter — no extra infrastructure needed)"
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
      class_option :breadcrumbs, type: :boolean, default: false, desc: "Enable breadcrumbs (request activity trail)"
      class_option :system_health, type: :boolean, default: false, desc: "Enable system health snapshot at error time"
      class_option :swallowed_exceptions, type: :boolean, default: false, desc: "Enable swallowed exception detection (Ruby 3.3+)"
      class_option :crash_capture, type: :boolean, default: false, desc: "Enable process crash capture via at_exit hook"
      class_option :diagnostic_dump, type: :boolean, default: false, desc: "Enable on-demand diagnostic dump"
      class_option :quick, type: :boolean, default: false, desc: "Zero-prompt install with sensible defaults (~60 seconds to working dashboard)"

      def welcome_message
        say "\n"
        say "=" * 70
        say "  Rails Error Dashboard Installation", :cyan
        say "  Quick mode: zero prompts, working dashboard in ~60 seconds", :yellow if quick_mode?
        say "=" * 70
        say "\n"
        say "Core features will be enabled automatically:", :green
        say "  ✓ Error capture (controllers, jobs, middleware)"
        say "  ✓ Dashboard UI at /red"
        say "  ✓ Real-time updates"
        say "  ✓ Analytics & spike detection"
        say "  ✓ 90-day error retention"
        say "\n"
      end

      def select_optional_features
        return unless behavior == :invoke

        if quick_mode?
          @selected_features = build_quick_defaults
          say "  Using sensible defaults (analytics ON, notifications OFF, breadcrumbs OFF)", :green
          return
        end

        return unless options[:interactive]
        return unless $stdin.tty?  # Skip interactive mode if not running in a terminal

        say "Let's configure optional features...\n", :cyan
        say "(You can always enable/disable these later in the initializer)\n\n", :yellow

        @selected_features = {}

        # =====================================================================
        # QUESTION 1: Notifications (gated — one y/N opens 5 sub-questions)
        # =====================================================================
        notification_keys = %i[slack email discord pagerduty webhooks]
        any_notification_cli_flag = notification_keys.any? { |k| options[k] }

        say "[1/3] Notifications [background/dashboard only — zero request overhead]", :cyan
        say "    Alert your team via Slack, email, Discord, PagerDuty, or webhooks.", :white

        if any_notification_cli_flag
          # Individual CLI flags passed — respect them, skip the gate prompt
          notification_keys.each { |k| @selected_features[k] = options[k] }
          say "    ✓ Using CLI flags for notification channels", :green
        else
          wants_notifications = ask("    Set up notifications? (y/N):", :yellow, limited_to: [ "y", "Y", "n", "N", "" ])
          if wants_notifications.downcase == "y"
            notification_channels = [
              { key: :slack,      name: "Slack",     hint: "SLACK_WEBHOOK_URL" },
              { key: :email,      name: "Email",     hint: "ERROR_NOTIFICATION_EMAILS" },
              { key: :discord,    name: "Discord",   hint: "DISCORD_WEBHOOK_URL" },
              { key: :pagerduty,  name: "PagerDuty", hint: "PAGERDUTY_INTEGRATION_KEY" },
              { key: :webhooks,   name: "Webhooks",  hint: "WEBHOOK_URLS" }
            ]
            notification_channels.each do |ch|
              r = ask("      #{ch[:name]}? (ENV[#{ch[:hint]}]) (y/N):", :yellow, limited_to: [ "y", "Y", "n", "N", "" ])
              @selected_features[ch[:key]] = r.downcase == "y"
            end
          else
            notification_keys.each { |k| @selected_features[k] = false }
            say "    ✓ Notifications off (enable anytime in initializer)", :white
          end
        end

        # =====================================================================
        # QUESTION 2: Advanced Analytics (grouped — defaults YES)
        # =====================================================================
        analytics_keys = %i[baseline_alerts similar_errors co_occurring_errors
                             error_cascades error_correlation platform_comparison occurrence_patterns]
        any_analytics_cli_flag = analytics_keys.any? { |k| options[k] }

        say "\n[2/3] Advanced Analytics (7 features) [background/dashboard only]", :cyan
        say "    Baseline alerts, fuzzy matching, co-occurring errors, cascade detection,", :white
        say "    correlation analysis, platform comparison, occurrence patterns.", :white
        say "    All run at query time or as background jobs — zero request-path overhead.", :white

        if any_analytics_cli_flag
          # Let create_initializer_file read options[] directly via the &.dig fallback
          say "    ✓ Using individual CLI flags for analytics", :white
        else
          response = ask("    Enable all? (Y/n):", :yellow, limited_to: [ "y", "Y", "n", "N", "" ])
          analytics_on = response.downcase != "n"
          analytics_keys.each { |k| @selected_features[k] = analytics_on }
          say analytics_on ? "    ✓ All 7 analytics features enabled" : "    ✗ Analytics disabled (enable individually in initializer)", analytics_on ? :green : :white
        end

        # =====================================================================
        # QUESTION 3: Advanced Options (gated — defaults NO)
        # =====================================================================
        advanced_keys = %i[async_logging error_sampling breadcrumbs system_health
                           source_code_integration git_blame swallowed_exceptions
                           crash_capture diagnostic_dump]
        any_advanced_cli_flag = advanced_keys.any? { |k| options[k] }

        say "\n[3/3] Advanced Options (performance tuning & diagnostics)", :cyan
        say "    Async logging, error sampling, breadcrumbs, system health,", :white
        say "    source code viewer, git blame, crash capture, and more.", :white

        if any_advanced_cli_flag
          # CLI flags passed — set them and skip the gate
          advanced_features = [
            { key: :async_logging,           name: "Async Logging",                  desc: "Process errors in background jobs [removes request-path overhead]" },
            { key: :error_sampling,          name: "Error Sampling",                 desc: "Log only % of non-critical errors [error-time only]" },
            { key: :breadcrumbs,             name: "Breadcrumbs",                    desc: "6 AS::Notifications subscribers: SQL, cache, jobs, mailers, Rack::Attack, ActionCable [request-path overhead]" },
            { key: :system_health,           name: "System Health Snapshot",         desc: "GC, memory, threads, connection pool at error time [error-time only]" },
            { key: :source_code_integration, name: "Source Code Integration",        desc: "Inline source viewer in error details [dashboard only]" },
            { key: :git_blame,               name: "Git Blame",                      desc: "Author, commit, timestamp per source line [dashboard only]" },
            { key: :swallowed_exceptions,    name: "Swallowed Exception Detection",  desc: "TracePoint(:rescue) catches silently rescued exceptions [request-path overhead, Ruby 3.3+]" },
            { key: :crash_capture,           name: "Process Crash Capture",          desc: "at_exit hook captures fatal crashes [error-time only]" },
            { key: :diagnostic_dump,         name: "Diagnostic Dump",                desc: "On-demand system snapshot via rake task [background/dashboard only]" }
          ]
          advanced_features.each { |f| @selected_features[f[:key]] = options[f[:key]] }
          say "    ✓ Using CLI flags for advanced options", :white
        else
          wants_advanced = ask("    Configure advanced options? (y/N):", :yellow, limited_to: [ "y", "Y", "n", "N", "" ])
          if wants_advanced.downcase == "y"
            advanced_features = [
              { key: :async_logging,           name: "Async Logging",                  desc: "Process errors in background jobs — removes overhead from request path [removes request-path overhead]" },
              { key: :error_sampling,          name: "Error Sampling",                 desc: "Log only % of non-critical errors to reduce volume [error-time only]" },
              { key: :breadcrumbs,             name: "Breadcrumbs",                    desc: "Subscribes 6 AS::Notifications: SQL, cache, jobs, mailers, Rack::Attack, ActionCable [request-path overhead]" },
              { key: :system_health,           name: "System Health Snapshot",         desc: "GC stats, memory (RSS/peak/swap), threads, connection pool at error time [error-time only]" },
              { key: :source_code_integration, name: "Source Code Integration",        desc: "View source code inline in error details (+/- 7 lines context) [dashboard only]" },
              { key: :git_blame,               name: "Git Blame Integration",          desc: "Show author, commit, timestamp for each source line (requires git) [dashboard only]" },
              { key: :swallowed_exceptions,    name: "Swallowed Exception Detection",  desc: "Detect silently rescued exceptions via TracePoint(:rescue) [request-path overhead, Ruby 3.3+]" },
              { key: :crash_capture,           name: "Process Crash Capture",          desc: "Capture fatal crashes via at_exit hook, written to disk [error-time only]" },
              { key: :diagnostic_dump,         name: "Diagnostic Dump",                desc: "On-demand system state snapshot via rake task or dashboard button [background/dashboard only]" }
            ]
            advanced_features.each do |f|
              say "\n    #{f[:name]}", :cyan
              say "    #{f[:desc]}", :white
              r = ask("    Enable? (y/N):", :yellow, limited_to: [ "y", "Y", "n", "N", "" ])
              @selected_features[f[:key]] = r.downcase == "y"
              if @selected_features[f[:key]] && f[:key] == :swallowed_exceptions && RUBY_VERSION < "3.3"
                say "    ⚠ Requires Ruby 3.3+ (you have #{RUBY_VERSION}) — will activate after upgrade", :yellow
              end
            end
          else
            # Set all advanced keys to false EXCEPT async_logging which defaults ON via class_option.
            # We do not set async_logging here so options[:async_logging] (default: true) wins in create_initializer_file.
            (advanced_keys - [ :async_logging ]).each { |k| @selected_features[k] = false }
            say "    ✓ Using defaults (async logging ON, everything else OFF)", :white
          end
        end

        say "\n"
      end

      def detect_existing_config
        initializer_path = File.join(destination_root, "config/initializers/rails_error_dashboard.rb")
        return unless File.exist?(initializer_path)

        content = File.read(initializer_path)
        @existing_install_detected = true

        # Detect separate database from existing config (skip comments)
        if content.match?(/^\s*config\.use_separate_database\s*=\s*true/)
          @database_mode = :separate
          @database_name = content[/^\s*config\.database\s*=\s*:(\w+)/, 1] || "error_dashboard"
          @enable_separate_database = true
          @application_name = detect_application_name
          say_status "detected", "existing separate database configuration", :green
        end
      end

      def select_database_mode
        # Skip if existing config already detected database mode
        return if @existing_install_detected && @database_mode

        # Quick mode: use shared DB, no prompt
        if quick_mode?
          @database_mode = :same
          @application_name = detect_application_name
          return
        end

        # Skip if not interactive or if --separate_database was passed via CLI
        if options[:separate_database]
          @database_mode = :separate
          @database_name = options[:database] || "error_dashboard"
          @application_name = detect_application_name
          return
        end

        return unless options[:interactive] && behavior == :invoke
        return unless $stdin.tty?

        say "-" * 70
        say "  Database Setup", :cyan
        say "-" * 70
        say "\n"
        say "  How do you want to store error data?\n", :white
        say "  1) Same database (default) - store errors in your app's primary database", :white
        say "  2) Separate database       - dedicated database for error data (recommended for production)", :white
        say "  3) Shared database          - connect to an existing error database shared by multiple apps", :white
        say "\n"

        response = ask("  Choose (1/2/3):", :yellow, limited_to: [ "1", "2", "3", "" ])

        case response
        when "2"
          @database_mode = :separate
          @database_name = "error_dashboard"
          @application_name = detect_application_name

          say "\n  Database key: error_dashboard", :green
          say "  Application name: #{@application_name}", :green
          say "\n"
        when "3"
          @database_mode = :multi_app
          @database_name = "error_dashboard"
          @application_name = detect_application_name

          say "\n  Is this the first app using the shared error database,", :white
          say "  or are you connecting to one that already exists?\n", :white
          say "  a) First app  - create a new shared error database", :white
          say "  b) Existing   - connect to a database already used by another app", :white
          say "\n"

          shared_response = ask("  Choose (a/b):", :yellow, limited_to: [ "a", "A", "b", "B", "" ])

          if shared_response.downcase == "b"
            say "\n  Enter the base database name from your other app's database.yml.", :white
            say "  We'll append _development/_production automatically.", :white
            say "  (e.g., if your DB is 'my_errors_development', enter 'my_errors'):\n", :white
            @shared_db_name = ask("  Database name:", :yellow)
            @shared_db_name = @shared_db_name.strip
            # Strip environment suffixes in case the user pasted the full name
            @shared_db_name = @shared_db_name.sub(/_(development|production|test)$/, "")
            @shared_db_name = "shared_errors" if @shared_db_name.empty?
          else
            @shared_db_name = "shared_errors"
          end

          say "\n  Database key: error_dashboard", :green
          say "  Shared database: #{@shared_db_name}", :green
          say "  Application name: #{@application_name}", :green
          say "  This app will share the error database with your other apps.", :white
          say "\n"
        else
          @database_mode = :same
          @database_name = nil
          @application_name = detect_application_name
        end
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

        # Database mode (set by select_database_mode or CLI flags)
        @database_mode ||= :same
        @enable_separate_database = @database_mode == :separate || @database_mode == :multi_app
        @enable_multi_app = @database_mode == :multi_app
        # @database_name and @application_name are set by select_database_mode

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
        @enable_breadcrumbs = @selected_features&.dig(:breadcrumbs) || options[:breadcrumbs]
        @enable_system_health = @selected_features&.dig(:system_health) || options[:system_health]
        @enable_swallowed_exceptions = @selected_features&.dig(:swallowed_exceptions) || options[:swallowed_exceptions]
        @enable_crash_capture = @selected_features&.dig(:crash_capture) || options[:crash_capture]
        @enable_diagnostic_dump = @selected_features&.dig(:diagnostic_dump) || options[:diagnostic_dump]

        # Don't overwrite existing initializer on upgrade — user's config is precious
        if @existing_install_detected
          say_status "skip", "config/initializers/rails_error_dashboard.rb (preserving existing config)", :yellow
          return
        end

        template "initializer.rb", "config/initializers/rails_error_dashboard.rb"
      end

      def copy_migrations
        source_dir = File.expand_path("../../../../db/migrate", __dir__)
        migrate_subdir = @enable_separate_database ? "db/error_dashboard_migrate" : "db/migrate"
        target_dir = File.join(destination_root, migrate_subdir)

        FileUtils.mkdir_p(target_dir)

        # Check BOTH migration directories to prevent cross-directory duplication (#93)
        # A user who installed with separate DB and re-runs without the flag should not
        # get duplicate migrations in db/migrate/
        existing = Set.new
        [ "db/migrate", "db/error_dashboard_migrate" ].each do |dir|
          full_path = File.join(destination_root, dir)
          next unless Dir.exist?(full_path)
          Dir.glob(File.join(full_path, "*rails_error_dashboard*.rb")).each do |f|
            existing.add(File.basename(f).sub(/^\d+_/, ""))
          end
        end

        # Start after the highest timestamp already present, not at the current
        # clock. The counter increments per copied file, so a re-run that happens
        # within N seconds of the previous install (N = number of migrations)
        # would otherwise reuse numbers the first install already consumed —
        # and Rails aborts the whole `db:migrate` with "Multiple migrations have
        # the version number ...", so the upgrade silently applies nothing.
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
        highest_existing = [ "db/migrate", "db/error_dashboard_migrate" ].flat_map do |dir|
          full_path = File.join(destination_root, dir)
          next [] unless Dir.exist?(full_path)
          Dir.glob(File.join(full_path, "*.rb")).map { |f| File.basename(f)[/^\d+/].to_i }
        end.max
        timestamp = highest_existing + 1 if highest_existing && highest_existing >= timestamp

        Dir.glob(File.join(source_dir, "*.rb")).sort.each do |source_file|
          basename = File.basename(source_file)
          name_without_ts = basename.sub(/^\d+_/, "")
          suffixed = name_without_ts.sub(/\.rb$/, ".rails_error_dashboard.rb")

          next if existing.include?(suffixed)

          FileUtils.cp(source_file, File.join(target_dir, "#{timestamp}_#{suffixed}"))
          timestamp += 1
        end

        say_status "copied", "migrations to #{migrate_subdir}", :green
      end

      def add_route
        routes_path = File.join(destination_root, "config", "routes.rb")
        if File.exist?(routes_path) && File.read(routes_path).include?("RailsErrorDashboard::Engine")
          say_status "skip", "route already exists (RailsErrorDashboard::Engine is already mounted)", :yellow
          return
        end

        route "mount RailsErrorDashboard::Engine => '/red'  # RED (Rails Error Dashboard) — also works at /error_dashboard"
      end

      def show_feature_summary
        return unless behavior == :invoke

        say "\n"
        say "=" * 70
        say "  Installation Complete!", :green
        say "=" * 70
        say "\n"

        say "Core Features (Always ON):", :cyan
        say "  ✓ Error Capture", :green
        say "  ✓ Dashboard UI", :green
        say "  ✓ Real-time Updates", :green
        say "  ✓ Analytics", :green
        say "  ✓ Async Logging (Rails :async adapter — no extra infrastructure needed)", :green

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
        developer_tools_features << "Breadcrumbs" if @enable_breadcrumbs
        developer_tools_features << "System Health" if @enable_system_health
        developer_tools_features << "Swallowed Exception Detection" if @enable_swallowed_exceptions
        developer_tools_features << "Process Crash Capture" if @enable_crash_capture
        developer_tools_features << "Diagnostic Dump" if @enable_diagnostic_dump

        if developer_tools_features.any?
          say "\nDeveloper Tools:", :cyan
          say "  ✓ #{developer_tools_features.join(", ")}", :green
          enabled_count += developer_tools_features.size
        end

        say "\nData Retention:", :cyan
        say "  Default: 90 days (change via config.retention_days)", :white
        say "  Manual cleanup: rails error_dashboard:retention_cleanup", :white
        say "  Schedule daily: RailsErrorDashboard::RetentionCleanupJob.perform_later", :white

        say "\n"
        say "Configuration Required:", :yellow if enabled_count > 0
        say "  → Edit config/initializers/rails_error_dashboard.rb", :yellow if @enable_error_sampling
        say "  → Set SLACK_WEBHOOK_URL in .env", :yellow if @enable_slack
        say "  → Set ERROR_NOTIFICATION_EMAILS in .env", :yellow if @enable_email
        say "  → Set DISCORD_WEBHOOK_URL in .env", :yellow if @enable_discord
        say "  → Set PAGERDUTY_INTEGRATION_KEY in .env", :yellow if @enable_pagerduty
        say "  → Set WEBHOOK_URLS in .env", :yellow if @enable_webhooks
        if @enable_async_logging
          # Check which async adapter is in use — only warn about external workers when needed
          async_section = File.exist?(File.join(destination_root, "config/initializers/rails_error_dashboard.rb")) &&
                          File.read(File.join(destination_root, "config/initializers/rails_error_dashboard.rb"))
          if async_section && (async_section.include?("async_adapter = :sidekiq") || async_section.include?("async_adapter = :solid_queue"))
            say "  → Ensure your background worker (Sidekiq/SolidQueue) is running for async logging", :yellow
          else
            say "  ✓ Async logging uses Rails :async adapter — no extra process needed", :green
          end
        end

        # Database-specific instructions
        if @enable_separate_database
          show_database_setup_instructions
        end

        say "\n"
        say "Next Steps:", :cyan
        if @enable_separate_database
          say "  1. Add the database.yml entry shown above"
          say "  2. Run: rails db:create:error_dashboard"
          if @enable_multi_app
            say "  3. Run migrations (only needed on the FIRST app):"
            say "     rails db:migrate:error_dashboard"
          else
            say "  3. Run: rails db:migrate:error_dashboard"
          end
          say "  4. Update credentials in config/initializers/rails_error_dashboard.rb"
          say "  5. Restart your Rails server"
          say "  6. Visit http://localhost:3000/red"
          say "  7. Verify: rails error_dashboard:verify"
        else
          say "  1. Run: rails db:migrate"
          say "  2. Update credentials in config/initializers/rails_error_dashboard.rb"
          say "  3. Restart your Rails server"
          say "  4. Visit http://localhost:3000/red"
        end
        say "Authentication:", :cyan
        say "  Default: HTTP Basic Auth (gandalf/youshallnotpass)", :white
        say "  Devise/Warden: config.authenticate_with = -> { warden.authenticated? }", :white
        say "  Session-based: config.authenticate_with = -> { session[:admin] == true }", :white
        say "  See: https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/guides/CONFIGURATION.md#custom-authentication", :white
        say "\n"
        say "Issue Tracking (optional):", :cyan
        say "  Create a dedicated RED (Rails Error Dashboard) bot account on your platform:", :white
        say "  GitHub:   github.com/join → username: 'red-bot' or 'yourapp-red'", :white
        say "  GitLab:   Use a Project Access Token (Settings > Access Tokens)", :white
        say "  Codeberg: codeberg.org → username: 'red-bot'", :white
        say "  Then: config.issue_tracker_token = ENV['RED_BOT_TOKEN']", :white
        say "  Issues will appear as created by your RED bot account.", :white
        say "\n"
        say "Documentation:", :white
        say "   Quick Start: https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/QUICKSTART.md", :white
        say "   Database Setup: https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/guides/DATABASE_OPTIONS.md", :white
        say "   Feature Guide: https://github.com/AnjanJ/rails_error_dashboard/blob/main/docs/FEATURES.md", :white
        say "\n"
        say "To enable/disable features later:", :white
        say "   Edit config/initializers/rails_error_dashboard.rb", :white
        say "\n"
      end

      def show_readme
        # Skip the old README display since we have the new summary
      end

      private

      def quick_mode?
        options[:quick]
      end

      def build_quick_defaults
        {
          # Async ON (built-in Rails :async adapter, zero infrastructure)
          async_logging: true,
          # All analytics ON — run at query/background time, zero request-path overhead
          baseline_alerts: true,
          similar_errors: true,
          co_occurring_errors: true,
          error_cascades: true,
          error_correlation: true,
          platform_comparison: true,
          occurrence_patterns: true,
          # ON — small overhead, high insight value
          breadcrumbs: true,       # ~0.1ms per request — SQL, cache, job trail leading to each error
          system_health: true,     # ~1ms per error — GC, memory, threads at exact error moment
          error_sampling: true,    # 50% sampling on non-critical errors — halves storage, still shows patterns
          # OFF — require credentials, config, or niche use case
          slack: false, email: false, discord: false, pagerduty: false, webhooks: false,
          source_code_integration: false,
          git_blame: false,
          swallowed_exceptions: false,
          crash_capture: false,
          diagnostic_dump: false
        }
      end

      def detect_application_name
        if defined?(Rails) && Rails.application
          Rails.application.class.module_parent_name
        else
          "MyApp"
        end
      end

      def show_database_setup_instructions
        app_name_snake = @application_name.to_s.underscore

        say "\n"
        say "-" * 70
        say "  Database Setup Required", :yellow
        say "-" * 70
        say "\n"
        say "  Add this to your config/database.yml:\n", :white

        if @enable_multi_app
          say "  # Shared error database (same physical DB across all your apps)", :white
        else
          say "  # Separate error database", :white
        end

        say "\n  development:", :cyan
        say "    primary:", :white
        say "      <<: *default", :white
        say "      database: #{app_name_snake}_development", :white
        say "    error_dashboard:", :white
        say "      <<: *default", :white
        if @enable_multi_app
          shared_db_base = @shared_db_name || "shared_errors"
          say "      database: #{shared_db_base}_development", :white
        else
          say "      database: #{app_name_snake}_errors_development", :white
        end
        say "      migrations_paths: db/error_dashboard_migrate", :white

        say "\n  production:", :cyan
        say "    primary:", :white
        say "      <<: *default", :white
        say "      database: #{app_name_snake}_production", :white
        say "    error_dashboard:", :white
        say "      <<: *default", :white
        if @enable_multi_app
          shared_db_base = @shared_db_name || "shared_errors"
          say "      database: #{shared_db_base}_production", :white
        else
          say "      database: #{app_name_snake}_errors_production", :white
        end
        say "      migrations_paths: db/error_dashboard_migrate", :white
        say "\n"

        if @enable_multi_app
          say "  For multi-app: all apps must point to the same physical database.", :yellow
          say "  Only the FIRST app needs to run migrations.", :yellow
          say "  Other apps just need the database.yml entry and 'rails error_dashboard:verify'.", :yellow
          say "\n"
        end
      end
    end
  end
end
