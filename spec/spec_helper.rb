# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/spec/'
  add_filter '/config/'
  add_group 'Commands', 'lib/rails_error_dashboard/commands'
  add_group 'Queries', 'lib/rails_error_dashboard/queries'
  add_group 'Services', 'lib/rails_error_dashboard/services'
  add_group 'Value Objects', 'lib/rails_error_dashboard/value_objects'
  add_group 'Models', 'app/models'
  add_group 'Controllers', 'app/controllers'
  add_group 'Jobs', 'app/jobs'
  add_group 'Mailers', 'app/mailers'
  minimum_coverage 80
end

require File.expand_path('dummy/config/environment.rb', __dir__)

# Store original root path before loading RSpec Rails
ORIGINAL_ROOT = File.expand_path('..', __dir__)

require 'rspec/rails'
require 'factory_bot_rails'
require 'faker'
require 'webmock/rspec'
require 'vcr'
require 'database_cleaner/active_record'

# Require support files
Dir[File.join(ORIGINAL_ROOT, 'spec', 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  # Configure spec file pattern to use original root
  config.pattern = File.join(ORIGINAL_ROOT, 'spec', '**', '*_spec.rb')

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = File.join(ORIGINAL_ROOT, 'spec', 'examples.txt')
  config.disable_monkey_patching!
  config.warnings = false
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods

  # Disable external HTTP requests
  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end

# VCR configuration
VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.ignore_localhost = true
end
