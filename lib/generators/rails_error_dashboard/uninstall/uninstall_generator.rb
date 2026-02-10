# frozen_string_literal: true

module RailsErrorDashboard
  module Generators
    class UninstallGenerator < Rails::Generators::Base
      desc "Uninstalls Rails Error Dashboard and removes all associated files and data"

      class_option :keep_data, type: :boolean, default: false, desc: "Keep error data in database (don't drop tables)"
      class_option :skip_confirmation, type: :boolean, default: false, desc: "Skip confirmation prompts"
      class_option :manual_only, type: :boolean, default: false, desc: "Show manual instructions only, don't perform automated uninstall"

      def welcome_message
        say "\n"
        say "=" * 80
        say "  🗑️  Rails Error Dashboard - Uninstall", :red
        say "=" * 80
        say "\n"
        say "This will remove Rails Error Dashboard from your application.", :yellow
        say "\n"
      end

      def detect_installed_components
        @components = {
          initializer: File.exist?("config/initializers/rails_error_dashboard.rb"),
          route: route_mounted?,
          migrations: migrations_exist?,
          tables: tables_exist?,
          gemfile: gemfile_includes_gem?
        }

        say "Detected components:", :cyan
        say "  #{status_icon(@components[:gemfile])} Gemfile entry"
        say "  #{status_icon(@components[:initializer])} Initializer (config/initializers/rails_error_dashboard.rb)"
        say "  #{status_icon(@components[:route])} Route (mount RailsErrorDashboard::Engine)"
        say "  #{status_icon(@components[:migrations])} Migrations (#{migration_count} files)"
        say "  #{status_icon(@components[:tables])} Database tables (#{table_count} tables)"
        say "\n"
      end

      def show_manual_instructions
        say "=" * 80
        say "  📖 Manual Uninstall Instructions", :cyan
        say "=" * 80
        say "\n"

        say "Step 1: Remove from Gemfile", :yellow
        say "  Open: Gemfile"
        say "  Remove: gem 'rails_error_dashboard'"
        say "  Run: bundle install"
        say "\n"

        if @components[:initializer]
          say "Step 2: Remove initializer", :yellow
          say "  Delete: config/initializers/rails_error_dashboard.rb"
          say "\n"
        end

        if @components[:route]
          say "Step 3: Remove route", :yellow
          say "  Open: config/routes.rb"
          say "  Remove: mount RailsErrorDashboard::Engine => '/error_dashboard'"
          say "\n"
        end

        if @components[:migrations]
          say "Step 4: Remove migrations", :yellow
          say "  Delete migration files from db/migrate/:"
          migration_files.each do |file|
            say "    - #{File.basename(file)}", :white
          end
          say "\n"
        end

        if @components[:tables]
          say "Step 5: Drop database tables (⚠️  DESTRUCTIVE - will delete all error data)", :yellow
          say "  Run: rails rails_error_dashboard:db:drop"
          say "  Or manually in rails console:"
          say "    ActiveRecord::Base.connection.execute('DROP TABLE rails_error_dashboard_error_logs')", :white
          say "    ActiveRecord::Base.connection.execute('DROP TABLE rails_error_dashboard_error_occurrences')", :white
          say "    ActiveRecord::Base.connection.execute('DROP TABLE rails_error_dashboard_cascade_patterns')", :white
          say "    ActiveRecord::Base.connection.execute('DROP TABLE rails_error_dashboard_error_baselines')", :white
          say "    ActiveRecord::Base.connection.execute('DROP TABLE rails_error_dashboard_error_comments')", :white
          say "    ActiveRecord::Migration.drop_table(:rails_error_dashboard_error_logs) rescue nil", :white
          say "\n"
        end

        say "Step 6: Clean up environment variables (optional)", :yellow
        say "  Remove from .env or environment:"
        say "    - ERROR_DASHBOARD_USER"
        say "    - ERROR_DASHBOARD_PASSWORD"
        say "    - SLACK_WEBHOOK_URL"
        say "    - ERROR_NOTIFICATION_EMAILS"
        say "    - DISCORD_WEBHOOK_URL"
        say "    - PAGERDUTY_INTEGRATION_KEY"
        say "    - WEBHOOK_URLS"
        say "    - DASHBOARD_BASE_URL"
        say "\n"

        say "Step 7: Restart your application", :yellow
        say "  Run: rails restart (or restart your server)"
        say "\n"

        say "=" * 80
        say "\n"
      end

      def confirm_automated_uninstall
        return if options[:manual_only]
        return if options[:skip_confirmation]

        say "Would you like to run the automated uninstall? (recommended)", :cyan
        say "This will:", :yellow
        say "  ✓ Remove initializer file"
        say "  ✓ Remove route from config/routes.rb"
        say "  ✓ Remove migration files"
        if options[:keep_data]
          say "  ✗ Keep database tables and data (--keep-data flag set)", :green
        else
          say "  ⚠️  Drop all database tables (deletes all error data!)", :red
        end
        say "\n"

        response = ask("Proceed with automated uninstall? (yes/no):", :yellow, limited_to: [ "yes", "no", "y", "n" ])

        if response.downcase == "no" || response.downcase == "n"
          say "\n"
          say "Automated uninstall cancelled.", :yellow
          say "Follow the manual instructions above to uninstall.", :cyan
          say "\n"
          exit 0
        end

        say "\n"
      end

      def final_data_warning
        return if options[:manual_only]
        return if options[:keep_data]
        return unless @components[:tables]

        say "=" * 80
        say "  ⚠️  FINAL WARNING - Data Deletion", :red
        say "=" * 80
        say "\n"
        say "You are about to PERMANENTLY DELETE all error tracking data!", :red
        say "\n"
        say "Database tables to be dropped:", :yellow
        table_names.each do |table|
          say "  • #{table}", :white
        end
        say "\n"
        say "This action CANNOT be undone!", :red
        say "\n"

        response = ask("Type 'DELETE ALL DATA' to confirm:", :red)

        if response != "DELETE ALL DATA"
          say "\n"
          say "Data deletion cancelled. Database tables will be kept.", :green
          say "Use --keep-data flag to skip this warning in the future.", :cyan
          @components[:tables] = false  # Don't drop tables
          say "\n"
        end

        say "\n"
      end

      def remove_initializer
        return if options[:manual_only]
        return unless @components[:initializer]

        remove_file "config/initializers/rails_error_dashboard.rb"
        say "  ✓ Removed initializer", :green
      end

      def remove_route
        return if options[:manual_only]
        return unless @components[:route]

        begin
          gsub_file "config/routes.rb", /mount RailsErrorDashboard::Engine.*\n/, ""
          say "  ✓ Removed route", :green
        rescue => e
          say "  ⚠️  Could not automatically remove route: #{e.message}", :yellow
          say "  Please manually remove: mount RailsErrorDashboard::Engine => '/error_dashboard'", :yellow
        end
      end

      def remove_migrations
        return if options[:manual_only]
        return unless @components[:migrations]

        migration_files.each do |file|
          remove_file file
        end
        say "  ✓ Removed #{migration_count} migration file(s)", :green
      end

      def drop_database_tables
        return if options[:manual_only]
        return if options[:keep_data]
        return unless @components[:tables]

        say "  Dropping database tables...", :yellow

        # Drop tables in reverse order (to respect foreign keys)
        tables_to_drop = [
          "rails_error_dashboard_error_comments",
          "rails_error_dashboard_error_occurrences",
          "rails_error_dashboard_cascade_patterns",
          "rails_error_dashboard_error_baselines",
          "rails_error_dashboard_error_logs"
        ]

        dropped_count = 0
        tables_to_drop.each do |table|
          if ActiveRecord::Base.connection.table_exists?(table)
            ActiveRecord::Base.connection.drop_table(table, if_exists: true)
            dropped_count += 1
          end
        rescue => e
          say "  ⚠️  Could not drop table #{table}: #{e.message}", :yellow
        end

        say "  ✓ Dropped #{dropped_count} database table(s)", :green
      end

      def show_completion_message
        return if options[:manual_only]

        say "\n"
        say "=" * 80
        say "  ✅ Uninstall Complete!", :green
        say "=" * 80
        say "\n"

        say "Remaining manual steps:", :cyan
        say "\n"

        say "1. Remove from Gemfile:", :yellow
        say "   Open: Gemfile"
        say "   Remove: gem 'rails_error_dashboard'"
        say "   Run: bundle install"
        say "\n"

        say "2. Restart your application:", :yellow
        say "   Run: rails restart"
        say "   Or: kill and restart your server process"
        say "\n"

        if options[:keep_data]
          say "3. Database tables were kept (--keep-data flag)", :green
          say "   To remove data later, run:", :yellow
          say "   rails generate rails_error_dashboard:uninstall", :yellow
          say "\n"
        end

        say "Clean up environment variables (optional):", :yellow
        say "  • ERROR_DASHBOARD_USER, ERROR_DASHBOARD_PASSWORD"
        say "  • SLACK_WEBHOOK_URL, ERROR_NOTIFICATION_EMAILS"
        say "  • DISCORD_WEBHOOK_URL, PAGERDUTY_INTEGRATION_KEY"
        say "  • WEBHOOK_URLS, DASHBOARD_BASE_URL"
        say "\n"

        say "Thank you for using Rails Error Dashboard! 👋", :cyan
        say "\n"
      end

      private

      def status_icon(present)
        present ? "✓" : "✗"
      end

      def route_mounted?
        return false unless File.exist?("config/routes.rb")
        File.read("config/routes.rb").include?("RailsErrorDashboard::Engine")
      end

      def migrations_exist?
        migration_files.any?
      end

      def migration_files
        Dir.glob("db/migrate/*rails_error_dashboard*.rb")
      end

      def migration_count
        migration_files.count
      end

      def tables_exist?
        return false unless defined?(ActiveRecord::Base)
        table_names.any? { |table| ActiveRecord::Base.connection.table_exists?(table) rescue false }
      end

      def table_names
        [
          "rails_error_dashboard_error_logs",
          "rails_error_dashboard_error_occurrences",
          "rails_error_dashboard_cascade_patterns",
          "rails_error_dashboard_error_baselines",
          "rails_error_dashboard_error_comments"
        ]
      end

      def table_count
        table_names.count { |table| ActiveRecord::Base.connection.table_exists?(table) rescue false }
      end

      def gemfile_includes_gem?
        return false unless File.exist?("Gemfile")
        File.read("Gemfile").match?(/gem\s+['"]rails_error_dashboard['"]/)
      end
    end
  end
end
