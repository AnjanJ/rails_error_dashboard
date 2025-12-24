require "rails_error_dashboard/version"
require "rails_error_dashboard/engine"
require "rails_error_dashboard/configuration"

# Core library files
require "rails_error_dashboard/value_objects/error_context"
require "rails_error_dashboard/services/platform_detector"
require "rails_error_dashboard/commands/log_error"
require "rails_error_dashboard/commands/resolve_error"
require "rails_error_dashboard/queries/errors_list"
require "rails_error_dashboard/queries/dashboard_stats"
require "rails_error_dashboard/queries/analytics_stats"
require "rails_error_dashboard/queries/filter_options"
require "rails_error_dashboard/error_reporter"
require "rails_error_dashboard/middleware/error_catcher"

module RailsErrorDashboard
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  # Initialize with default configuration
  self.configuration = Configuration.new
end
