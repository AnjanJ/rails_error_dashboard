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
