# frozen_string_literal: true

require 'rails/all'
require_relative '../../../lib/rails_error_dashboard'

module Dummy
  class Application < Rails::Application
    # Set root to the dummy app directory so Rails can find config files
    config.root = File.expand_path('..', __dir__)

    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.secret_key_base = 'test_secret_key_base'
  end
end
