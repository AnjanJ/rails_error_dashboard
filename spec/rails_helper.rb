# frozen_string_literal: true

require 'spec_helper'

# Load the database schema if the database doesn't have tables yet
ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  # Enable transactional fixtures
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # ActiveJob test adapter
  config.include ActiveJob::TestHelper
  config.before(:each) do
    clear_enqueued_jobs
    clear_performed_jobs
  end
end
