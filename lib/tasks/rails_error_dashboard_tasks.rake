# frozen_string_literal: true

namespace :rails_error_dashboard do
  desc "Fill in environment on error logs captured before the column existed (from environment_info.rails_env)"
  task backfill_environments: :environment do
    updated = RailsErrorDashboard::Commands::BackfillEnvironments.call
    puts "rails_error_dashboard: backfilled environment on #{updated} error log(s)."
  end

  namespace :db do
    desc "Drop all Rails Error Dashboard database tables (⚠️  DESTRUCTIVE - deletes all error data)"
    task drop: :environment do
      puts "\n"
      puts "=" * 80
      puts "  ⚠️  Rails Error Dashboard - Drop Database Tables"
      puts "=" * 80
      puts "\n"

      # List tables that will be dropped
      tables_to_drop = [
        "rails_error_dashboard_error_comments",
        "rails_error_dashboard_error_occurrences",
        "rails_error_dashboard_cascade_patterns",
        "rails_error_dashboard_error_baselines",
        "rails_error_dashboard_error_logs"
      ]

      existing_tables = tables_to_drop.select do |table|
        ActiveRecord::Base.connection.table_exists?(table)
      end

      if existing_tables.empty?
        puts "No Rails Error Dashboard tables found in the database."
        puts "\n"
        exit 0
      end

      puts "The following tables will be PERMANENTLY DELETED:"
      existing_tables.each do |table|
        record_count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table}").first.values.first rescue 0
        puts "  • #{table} (#{record_count} records)"
      end
      puts "\n"
      puts "⚠️  This action CANNOT be undone!"
      puts "\n"

      # Ask for confirmation
      print "Type 'DELETE ALL DATA' to confirm: "
      confirmation = $stdin.gets.chomp

      if confirmation != "DELETE ALL DATA"
        puts "\n"
        puts "Cancelled. No tables were dropped."
        puts "\n"
        exit 0
      end

      puts "\n"
      puts "Dropping tables..."

      # Drop tables in reverse order (respects foreign keys)
      dropped_count = 0
      existing_tables.reverse.each do |table|
        begin
          ActiveRecord::Base.connection.drop_table(table, if_exists: true)
          puts "  ✓ Dropped #{table}"
          dropped_count += 1
        rescue => e
          puts "  ✗ Failed to drop #{table}: #{e.message}"
        end
      end

      puts "\n"
      puts "=" * 80
      puts "  ✅ Successfully dropped #{dropped_count} table(s)"
      puts "=" * 80
      puts "\n"
      puts "Next steps:"
      puts "  1. Remove gem 'rails_error_dashboard' from Gemfile"
      puts "  2. Run: bundle install"
      puts "  3. Remove initializer: config/initializers/rails_error_dashboard.rb"
      puts "  4. Remove route from config/routes.rb"
      puts "  5. Delete migration files: db/migrate/*rails_error_dashboard*.rb"
      puts "  6. Restart your Rails server"
      puts "\n"
      puts "Or use the automated uninstaller:"
      puts "  rails generate rails_error_dashboard:uninstall"
      puts "\n"
    end
  end
end
