# frozen_string_literal: true

# Abstract base class for models stored in the error dashboard database
#
# By default, this connects to the same database as the main application.
#
# To enable a separate error dashboard database:
# 1. Set config.use_separate_database = true in the gem configuration
# 2. Set config.database = :error_dashboard in the gem configuration
# 3. Add an "error_dashboard:" entry in config/database.yml
# 4. Run: rails db:create:error_dashboard
# 5. Run: rails db:migrate:error_dashboard
#
# For multi-app setups, point all apps' database.yml "error_dashboard:" entry
# to the same physical database. Each app is identified by config.application_name.
#
# Run "rails error_dashboard:verify" to check your setup.
#
# Benefits of separate database:
# - Performance isolation (error logging doesn't slow down user requests)
# - Independent scaling (can put error DB on separate server)
# - Multi-app support (centralized error tracking across multiple Rails apps)
# - Different retention policies (archive old errors without affecting main data)
#
# Trade-offs:
# - No foreign keys between error_logs and users tables
# - No joins across databases (Rails handles with separate queries)
# - Slightly more complex operations (need to manage 2 databases)

module RailsErrorDashboard
  class ErrorLogsRecord < ActiveRecord::Base
    self.abstract_class = true

    # Database connection will be configured by the engine initializer
    # after the user's configuration is loaded
    # See lib/rails_error_dashboard/engine.rb
  end
end
