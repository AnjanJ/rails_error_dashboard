# frozen_string_literal: true

namespace :error_dashboard do
  desc "Verify Rails Error Dashboard setup (database, tables, configuration)"
  task verify: :environment do
    puts "\n" + "=" * 70
    puts "  RAILS ERROR DASHBOARD - SETUP VERIFICATION"
    puts "=" * 70

    checks_passed = 0
    checks_failed = 0
    warnings = 0

    # 1. Configuration check
    print "\n  Checking configuration... "
    config = RailsErrorDashboard.configuration
    begin
      config.validate!
      puts "OK"
      checks_passed += 1
    rescue RailsErrorDashboard::ConfigurationError => e
      puts "FAILED"
      puts "    Error: #{e.message}"
      checks_failed += 1
    end

    # 2. Database mode
    print "  Database mode... "
    if config.use_separate_database
      db_name = config.database || :error_dashboard
      puts "SEPARATE (key: #{db_name})"
    else
      puts "SHARED (using primary database)"
    end
    checks_passed += 1

    # 3. Database connection
    print "  Database connection... "
    begin
      RailsErrorDashboard::ErrorLogsRecord.connection.active?
      adapter = RailsErrorDashboard::ErrorLogsRecord.connection.adapter_name
      puts "OK (#{adapter})"
      checks_passed += 1
    rescue => e
      puts "FAILED"
      puts "    Error: #{e.message}"
      if config.use_separate_database
        db_name = config.database || :error_dashboard
        puts "    Hint: Make sure '#{db_name}:' is configured in config/database.yml"
        puts "    Hint: Run 'rails db:create:#{db_name}' to create the database"
      end
      checks_failed += 1
    end

    # 4. Tables check
    print "  Required tables... "
    required_tables = %w[
      rails_error_dashboard_applications
      rails_error_dashboard_error_logs
      rails_error_dashboard_error_occurrences
      rails_error_dashboard_error_comments
      rails_error_dashboard_error_baselines
      rails_error_dashboard_cascade_patterns
    ]

    begin
      conn = RailsErrorDashboard::ErrorLogsRecord.connection
      existing = required_tables.select { |t| conn.table_exists?(t) }
      missing = required_tables - existing

      if missing.empty?
        puts "OK (#{existing.size} tables found)"
        checks_passed += 1
      else
        puts "INCOMPLETE"
        missing.each { |t| puts "    Missing: #{t}" }
        if config.use_separate_database
          db_name = config.database || :error_dashboard
          puts "    Hint: Run 'rails db:migrate:#{db_name}'"
        else
          puts "    Hint: Run 'rails db:migrate'"
        end
        checks_failed += 1
      end
    rescue => e
      puts "SKIPPED (no connection)"
    end

    # 5. Application registration
    print "  Application registration... "
    begin
      app_name = config.application_name ||
                 ENV["APPLICATION_NAME"] ||
                 (defined?(Rails) && Rails.application.class.module_parent_name) ||
                 "Unknown"

      current_app = RailsErrorDashboard::Application.find_by(name: app_name)
      if current_app
        puts "OK"
        puts "    This app: \"#{app_name}\" (ID: #{current_app.id})"
        checks_passed += 1
      else
        puts "PENDING"
        puts "    App \"#{app_name}\" will be registered on first error"
        warnings += 1
      end

      # List other registered apps
      all_apps = RailsErrorDashboard::Application.order(:name).pluck(:name, :id)
      other_apps = all_apps.reject { |name, _| name == app_name }
      if other_apps.any?
        puts "    Other apps in this database:"
        other_apps.each { |name, id| puts "      - \"#{name}\" (ID: #{id})" }
      end
    rescue => e
      puts "SKIPPED (#{e.message.truncate(60)})"
    end

    # 6. Error count
    print "  Error data... "
    begin
      total = RailsErrorDashboard::ErrorLog.count
      unresolved = RailsErrorDashboard::ErrorLog.where(resolved: false).count
      puts "#{total} total errors (#{unresolved} unresolved)"
      checks_passed += 1
    rescue => e
      puts "SKIPPED (#{e.message.truncate(60)})"
    end

    # 7. Authentication check
    print "  Authentication... "
    if config.dashboard_username == "gandalf" && config.dashboard_password == "youshallnotpass"
      if Rails.env.production?
        puts "WARNING - using default credentials in production!"
        checks_failed += 1
      else
        puts "OK (default credentials - change before production)"
        warnings += 1
      end
    else
      puts "OK (custom credentials)"
      checks_passed += 1
    end

    # Summary
    puts "\n" + "-" * 70
    puts "  Results: #{checks_passed} passed, #{checks_failed} failed, #{warnings} warnings"

    if checks_failed > 0
      puts "  Status: NEEDS ATTENTION"
    elsif warnings > 0
      puts "  Status: OK (with warnings)"
    else
      puts "  Status: ALL GOOD"
    end

    puts "=" * 70 + "\n"
  end

  desc "List all registered applications with error counts"
  task list_applications: :environment do
    puts "\n" + "=" * 80
    puts "RAILS ERROR DASHBOARD - REGISTERED APPLICATIONS"
    puts "=" * 80

    # Use single SQL query with aggregates to avoid N+1 queries
    # This fetches all app data + error counts in one query instead of 6N queries
    apps = RailsErrorDashboard::Application
             .select("rails_error_dashboard_applications.*")
             .select("COUNT(rails_error_dashboard_error_logs.id) as total_errors")
             .select("COALESCE(SUM(CASE WHEN NOT rails_error_dashboard_error_logs.resolved THEN 1 ELSE 0 END), 0) as unresolved_errors")
             .joins("LEFT JOIN rails_error_dashboard_error_logs ON rails_error_dashboard_error_logs.application_id = rails_error_dashboard_applications.id")
             .group("rails_error_dashboard_applications.id")
             .order(:name)

    if apps.empty?
      puts "\nNo applications registered yet."
      puts "Applications are auto-registered when they log their first error."
      puts "\n" + "=" * 80 + "\n"
      next
    end

    puts "\n#{apps.count} application(s) registered:\n\n"

    # Calculate column widths using aggregated data (no additional queries)
    name_width = [ apps.map(&:name).map(&:length).max, 20 ].max
    total_width = [ apps.map(&:total_errors).map(&:to_s).map(&:length).max, 5 ].max
    unresolved_width = [ apps.map(&:unresolved_errors).map(&:to_s).map(&:length).max, 10 ].max

    # Print header
    printf "%-#{name_width}s  %#{total_width}s  %#{unresolved_width}s  %s\n",
           "APPLICATION", "TOTAL", "UNRESOLVED", "CREATED"
    puts "-" * 80

    # Print each application (total_errors and unresolved_errors are already loaded as attributes)
    apps.each do |app|
      printf "%-#{name_width}s  %#{total_width}d  %#{unresolved_width}d  %s\n",
             app.name,
             app.total_errors.to_i,
             app.unresolved_errors.to_i,
             app.created_at.strftime("%Y-%m-%d %H:%M")
    end

    puts "\n" + "=" * 80

    # Summary stats using already-loaded aggregates (no additional queries)
    total_errors = apps.sum(&:total_errors)
    total_unresolved = apps.sum(&:unresolved_errors)

    puts "\nSUMMARY:"
    puts "  Total Applications: #{apps.count}"
    puts "  Total Errors: #{total_errors}"
    puts "  Total Unresolved: #{total_unresolved}"
    puts "  Resolution Rate: #{total_errors.zero? ? 'N/A' : "#{((total_errors - total_unresolved).to_f / total_errors * 100).round(1)}%"}"

    puts "\n" + "=" * 80 + "\n"
  end

  desc "Backfill application_id for existing errors"
  task backfill_application: :environment do
    app_name = ENV["APP_NAME"] || ENV["APPLICATION_NAME"] ||
               (defined?(Rails) && Rails.application.class.module_parent_name) ||
               "Legacy Application"

    puts "\n" + "=" * 80
    puts "RAILS ERROR DASHBOARD - BACKFILL APPLICATION"
    puts "=" * 80
    puts "\nApplication Name: #{app_name}"

    # Check if there are any errors without application
    orphaned_count = RailsErrorDashboard::ErrorLog.where(application_id: nil).count

    if orphaned_count.zero?
      puts "\n✓ No errors found without application_id"
      puts "  All errors are already associated with an application."
      puts "\n" + "=" * 80 + "\n"
      next
    end

    puts "Errors to backfill: #{orphaned_count}"

    # Find or create application
    app = RailsErrorDashboard::Application.find_or_create_by!(name: app_name) do |a|
      a.description = "Backfilled via rake task on #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    end

    puts "Using application: #{app.name} (ID: #{app.id})"

    # Confirm before proceeding
    print "\nProceed with backfill? (y/N): "
    confirmation = $stdin.gets.chomp.downcase

    unless confirmation == "y" || confirmation == "yes"
      puts "\n✗ Backfill cancelled"
      puts "\n" + "=" * 80 + "\n"
      next
    end

    puts "\nBackfilling errors..."
    count = 0
    start_time = Time.current

    # Process in batches with progress indicator
    RailsErrorDashboard::ErrorLog.where(application_id: nil).find_in_batches(batch_size: 1000) do |batch|
      batch.each do |error|
        error.update_column(:application_id, app.id)
        count += 1
        print "." if count % 100 == 0
      end
    end

    elapsed = (Time.current - start_time).round(2)

    puts "\n\n✓ Backfill complete!"
    puts "  Processed: #{count} errors"
    puts "  Time elapsed: #{elapsed} seconds"
    puts "  Rate: #{(count / elapsed).round(0)} errors/sec"

    puts "\n" + "=" * 80 + "\n"
  end

  desc "Show application statistics and health metrics"
  task app_stats: :environment do
    app_id = ENV["APP_ID"]
    app_name = ENV["APP_NAME"]

    puts "\n" + "=" * 80
    puts "RAILS ERROR DASHBOARD - APPLICATION STATISTICS"
    puts "=" * 80

    # Find application
    app = if app_id
            RailsErrorDashboard::Application.find_by(id: app_id)
    elsif app_name
            RailsErrorDashboard::Application.find_by(name: app_name)
    else
            puts "\n✗ Please specify APP_ID or APP_NAME"
            puts "\nExamples:"
            puts "  rails error_dashboard:app_stats APP_NAME='My App'"
            puts "  rails error_dashboard:app_stats APP_ID=1"
            puts "\n" + "=" * 80 + "\n"
            next
    end

    unless app
      puts "\n✗ Application not found"
      puts "\n" + "=" * 80 + "\n"
      next
    end

    # Display application info
    puts "\nApplication: #{app.name}"
    puts "Created: #{app.created_at.strftime('%Y-%m-%d %H:%M')}"
    puts "Description: #{app.description || 'N/A'}"
    puts "\n" + "-" * 80

    # Error counts
    errors = app.error_logs
    puts "\nERROR COUNTS:"
    puts "  Total: #{errors.count}"
    puts "  Unresolved: #{errors.unresolved.count}"
    puts "  Resolved: #{errors.resolved.count}"
    puts "  Resolution Rate: #{errors.count.zero? ? 'N/A' : "#{(errors.resolved.count.to_f / errors.count * 100).round(1)}%"}"

    # Time-based stats
    puts "\nTIME-BASED STATS:"
    puts "  Last 24 hours: #{errors.where('occurred_at >= ?', 24.hours.ago).count}"
    puts "  Last 7 days: #{errors.where('occurred_at >= ?', 7.days.ago).count}"
    puts "  Last 30 days: #{errors.where('occurred_at >= ?', 30.days.ago).count}"

    # Top error types
    puts "\nTOP 5 ERROR TYPES:"
    top_errors = errors.group(:error_type).count.sort_by { |_, count| -count }.first(5)
    if top_errors.any?
      top_errors.each_with_index do |(error_type, count), index|
        puts "  #{index + 1}. #{error_type}: #{count}"
      end
    else
      puts "  No errors logged yet"
    end

    # Platform breakdown
    platforms = errors.group(:platform).count
    if platforms.any?
      puts "\nPLATFORM BREAKDOWN:"
      platforms.sort_by { |_, count| -count }.each do |platform, count|
        platform_name = platform || "Unknown"
        percentage = (count.to_f / errors.count * 100).round(1)
        puts "  #{platform_name}: #{count} (#{percentage}%)"
      end
    end

    # Recent activity
    recent = errors.order(occurred_at: :desc).limit(5)
    if recent.any?
      puts "\nRECENT ERRORS:"
      recent.each do |error|
        time_ago = Time.current - error.occurred_at
        time_str = if time_ago < 3600
                     "#{(time_ago / 60).to_i}m ago"
        elsif time_ago < 86400
                     "#{(time_ago / 3600).to_i}h ago"
        else
                     "#{(time_ago / 86400).to_i}d ago"
        end
        puts "  • #{error.error_type} (#{time_str}) - #{error.message.truncate(50)}"
      end
    end

    puts "\n" + "=" * 80 + "\n"
  end

  desc "Clean up old resolved errors"
  task cleanup_resolved: :environment do
    days = ENV["DAYS"]&.to_i || 90
    app_name = ENV["APP_NAME"]

    puts "\n" + "=" * 80
    puts "RAILS ERROR DASHBOARD - CLEANUP RESOLVED ERRORS"
    puts "=" * 80
    puts "\nCleaning up resolved errors older than #{days} days"

    scope = RailsErrorDashboard::ErrorLog.resolved
                                         .where("resolved_at < ?", days.days.ago)

    if app_name
      app = RailsErrorDashboard::Application.find_by(name: app_name)
      unless app
        puts "\n✗ Application '#{app_name}' not found"
        puts "\n" + "=" * 80 + "\n"
        next
      end
      scope = scope.where(application: app)
      puts "Filtering to application: #{app_name}"
    end

    count = scope.count

    if count.zero?
      puts "\n✓ No resolved errors found older than #{days} days"
      puts "\n" + "=" * 80 + "\n"
      next
    end

    puts "Found #{count} resolved errors to delete"

    # Confirm before proceeding
    print "\nProceed with deletion? (y/N): "
    confirmation = $stdin.gets.chomp.downcase

    unless confirmation == "y" || confirmation == "yes"
      puts "\n✗ Cleanup cancelled"
      puts "\n" + "=" * 80 + "\n"
      next
    end

    puts "\nDeleting errors..."
    start_time = Time.current
    deleted = scope.delete_all
    elapsed = (Time.current - start_time).round(2)

    puts "\n✓ Cleanup complete!"
    puts "  Deleted: #{deleted} errors"
    puts "  Time elapsed: #{elapsed} seconds"

    puts "\n" + "=" * 80 + "\n"
  end
end
