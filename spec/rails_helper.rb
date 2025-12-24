# frozen_string_literal: true

require 'spec_helper'

RSpec.configure do |config|
  # Disable transactional fixtures until database is properly configured
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
