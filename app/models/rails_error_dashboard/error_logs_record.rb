# frozen_string_literal: true

# Abstract base class for models stored in the error dashboard database
#
# By default, this connects to the same database as the main application.
#
# To enable a separate error dashboard database:
# 1. Set use_separate_database: true in the gem configuration
# 2. Set database: :error_dashboard (or your custom name) in the gem configuration
# 3. Configure error_dashboard settings in config/database.yml
# 4. Run: rails db:create
# 5. Run: rails db:migrate
#
# Benefits of separate database:
# - Performance isolation (error logging doesn't slow down user requests)
# - Independent scaling (can put error DB on separate server)
# - Different retention policies (archive old errors without affecting main data)
# - Security isolation (different access controls for error logs)
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
