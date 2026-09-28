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

      # The connection RED's models use: the separate or shared error database
      # when there is one. Raises if the engine fell back to the primary one.
      connection = RailsErrorDashboard::Commands::DropAllTables.connection
      database = connection.pool.db_config.name
      plan = RailsErrorDashboard::Queries::UninstallPlan.call(connection)

      if plan.empty?
        puts "No Rails Error Dashboard tables found in the '#{database}' database."
        puts "\n"
        next
      end

      puts "The following tables in the '#{database}' database will be PERMANENTLY DELETED:"
      plan.each do |entry|
        puts "  • #{entry[:table]} (#{entry[:rows] || '?'} records)"
      end
      puts "\n"

      if plan.any? { |entry| entry[:table] == "rails_error_dashboard_applications" }
        names = connection.select_values("SELECT name FROM #{connection.quote_table_name('rails_error_dashboard_applications')} ORDER BY name")
        if names.size > 1
          puts "⚠️  This database holds errors for #{names.size} applications, and ALL of them will be deleted:"
          names.each { |name| puts "  • #{name}" }
          puts "\n"
        end
      end

      puts "⚠️  This action CANNOT be undone!"
      puts "\n"

      print "Type 'DELETE ALL DATA' to confirm: "
      confirmation = $stdin.gets.to_s.chomp

      if confirmation != "DELETE ALL DATA"
        puts "\n"
        puts "Cancelled. No tables were dropped."
        puts "\n"
        next
      end

      puts "\n"
      puts "Dropping tables..."
      dropped = RailsErrorDashboard::Commands::DropAllTables.call(connection: connection)
      dropped.each { |table| puts "  ✓ Dropped #{table}" }

      puts "\n"
      puts "=" * 80
      puts "  ✅ Successfully dropped #{dropped.size} table(s)"
      puts "=" * 80
      puts "\n"
      puts "Next steps:"
      puts "  1. Remove the initializer: config/initializers/rails_error_dashboard.rb"
      puts "  2. Remove the route from config/routes.rb (mount RailsErrorDashboard::Engine)"
      puts "  3. Delete RED's migrations: db/migrate/*rails_error_dashboard*.rb"
      puts "     (and db/error_dashboard_migrate/ with a separate database)"
      puts "  4. Separate database: remove its entry from config/database.yml"
      puts "  5. Regenerate the schema file: bin/rails db:schema:dump"
      puts "     (otherwise db:schema:load recreates these tables)"
      puts "  6. Remove gem 'rails_error_dashboard' from the Gemfile and run: bundle install"
      puts "  7. Restart your Rails server"
      puts "\n"
      puts "Or use the automated uninstaller, before removing the gem:"
      puts "  bin/rails generate rails_error_dashboard:uninstall"
      puts "\n"
    end
  end
end
