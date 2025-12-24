# frozen_string_literal: true

# Abstract base class for models stored in the error_logs database
#
# By default, this connects to the same database as the main application.
#
# To enable a separate error logs database:
# 1. Set use_separate_database: true in the gem configuration
# 2. Configure error_logs_database settings in config/database.yml
# 3. Run: rails db:create:error_logs
# 4. Run: rails db:migrate:error_logs
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

    # Connect to error_logs database (or primary if not using separate DB)
    # Only connect to separate database if configuration is enabled
    if RailsErrorDashboard.configuration&.use_separate_database
      connects_to database: { writing: :error_logs, reading: :error_logs }
    end
  end
end
