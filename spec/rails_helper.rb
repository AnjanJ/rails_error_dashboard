# frozen_string_literal: true

require 'spec_helper'

# Load the database schema if the database doesn't have tables yet
# Use schema.rb instead of maintaining migrations to avoid conflicts
# between gem migrations and dummy app migrations
ActiveRecord::Tasks::DatabaseTasks.load_schema_current

RSpec.configure do |config|
  # Enable transactional fixtures
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Clear cache before each test to prevent stale associations
  config.before(:each) do
    Rails.cache.clear
  end

  # Storm protection holds per-process state (breaker, buckets, counters).
  # Reset before each example so storm-spec state never leaks into
  # unrelated specs (config-pollution discipline).
  #
  # The config flag is also forced off here because the gem default is ON
  # and `RailsErrorDashboard.reset_configuration!` (used by many specs)
  # restores gem defaults, not dummy-initializer values — without this,
  # any spec that resets configuration re-enables storms for the rest of
  # the suite. Storm specs opt back in via their own (later-running) hooks.
  config.before(:each) do
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    RailsErrorDashboard.configuration.enable_storm_protection = false
  end

  # ActiveJob test adapter
  config.include ActiveJob::TestHelper
  config.before(:each) do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  # ActionMailer configuration
  config.before(:each) do
    ActionMailer::Base.deliveries.clear
    ActionMailer::Base.delivery_method = :test
  end
end
