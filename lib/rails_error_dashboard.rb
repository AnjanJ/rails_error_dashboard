require "rails_error_dashboard/version"
require "rails_error_dashboard/engine"
require "rails_error_dashboard/configuration"

# External dependencies
require "pagy"
require "browser"
require "groupdate"
require "httparty"

# Core library files
require "rails_error_dashboard/value_objects/error_context"
require "rails_error_dashboard/services/platform_detector"
require "rails_error_dashboard/commands/log_error"
require "rails_error_dashboard/commands/resolve_error"
require "rails_error_dashboard/commands/batch_resolve_errors"
require "rails_error_dashboard/commands/batch_delete_errors"
require "rails_error_dashboard/queries/errors_list"
require "rails_error_dashboard/queries/dashboard_stats"
require "rails_error_dashboard/queries/analytics_stats"
require "rails_error_dashboard/queries/filter_options"
require "rails_error_dashboard/error_reporter"
require "rails_error_dashboard/middleware/error_catcher"

# Plugin system
require "rails_error_dashboard/plugin"
require "rails_error_dashboard/plugin_registry"

module RailsErrorDashboard
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  # Register a plugin
  # @param plugin [Plugin] The plugin instance to register
  # @return [Boolean] True if registered successfully, false otherwise
  def self.register_plugin(plugin)
    PluginRegistry.register(plugin)
  end

  # Unregister a plugin by name
  # @param plugin_name [String] The name of the plugin to unregister
  def self.unregister_plugin(plugin_name)
    PluginRegistry.unregister(plugin_name)
  end

  # Get all registered plugins
  # @return [Array<Plugin>] List of registered plugins
  def self.plugins
    PluginRegistry.plugins
  end

  # Initialize with default configuration
  self.configuration = Configuration.new
end
