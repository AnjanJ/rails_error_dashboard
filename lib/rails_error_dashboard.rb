require "rails_error_dashboard/version"
require "rails_error_dashboard/engine"
require "rails_error_dashboard/configuration_error"
require "rails_error_dashboard/configuration"
require "rails_error_dashboard/logger"
require "rails_error_dashboard/manual_error_reporter"

# External dependencies
require "pagy"
require "pagy/extras/bootstrap"
require "browser"
require "groupdate"
require "httparty"
require "chartkick"
require "turbo-rails"


# Core library files
require "rails_error_dashboard/value_objects/error_context"
require "rails_error_dashboard/helpers/user_model_detector"
require "rails_error_dashboard/services/platform_detector"
require "rails_error_dashboard/services/backtrace_parser"
require "rails_error_dashboard/services/similarity_calculator"
require "rails_error_dashboard/services/cascade_detector"
require "rails_error_dashboard/services/baseline_calculator"
require "rails_error_dashboard/services/baseline_alert_throttler"
require "rails_error_dashboard/services/pattern_detector"
require "rails_error_dashboard/services/error_normalizer"
require "rails_error_dashboard/services/source_code_reader"
require "rails_error_dashboard/services/git_blame_reader"
require "rails_error_dashboard/services/github_link_generator"
require "rails_error_dashboard/queries/co_occurring_errors"
require "rails_error_dashboard/queries/error_cascades"
require "rails_error_dashboard/queries/baseline_stats"
require "rails_error_dashboard/queries/platform_comparison"
require "rails_error_dashboard/queries/error_correlation"
require "rails_error_dashboard/commands/log_error"
require "rails_error_dashboard/commands/resolve_error"
require "rails_error_dashboard/commands/batch_resolve_errors"
require "rails_error_dashboard/commands/batch_delete_errors"
require "rails_error_dashboard/commands/assign_error"
require "rails_error_dashboard/commands/unassign_error"
require "rails_error_dashboard/commands/update_error_priority"
require "rails_error_dashboard/commands/snooze_error"
require "rails_error_dashboard/commands/unsnooze_error"
require "rails_error_dashboard/commands/update_error_status"
require "rails_error_dashboard/commands/add_error_comment"
require "rails_error_dashboard/queries/errors_list"
require "rails_error_dashboard/queries/dashboard_stats"
require "rails_error_dashboard/queries/analytics_stats"
require "rails_error_dashboard/queries/filter_options"
require "rails_error_dashboard/queries/similar_errors"
require "rails_error_dashboard/queries/recurring_issues"
require "rails_error_dashboard/queries/mttr_stats"
require "rails_error_dashboard/queries/critical_alerts"
require "rails_error_dashboard/error_reporter"
require "rails_error_dashboard/middleware/error_catcher"
require "rails_error_dashboard/middleware/rate_limiter"

# Plugin system
require "rails_error_dashboard/plugin"
require "rails_error_dashboard/plugin_registry"

module RailsErrorDashboard
  class << self
    attr_writer :configuration

    # Get or initialize configuration
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure the gem
    def configure
      yield(configuration)
    end

    # Reset configuration to defaults
    def reset_configuration!
      @configuration = Configuration.new
    end
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

  # Register a callback for when any error is logged
  # @param block [Proc] The callback to execute, receives error_log as parameter
  # @example
  #   RailsErrorDashboard.on_error_logged do |error_log|
  #     puts "Error logged: #{error_log.error_type}"
  #   end
  def self.on_error_logged(&block)
    configuration.notification_callbacks[:error_logged] << block if block_given?
  end

  # Register a callback for when a critical error is logged
  # @param block [Proc] The callback to execute, receives error_log as parameter
  # @example
  #   RailsErrorDashboard.on_critical_error do |error_log|
  #     PagerDuty.trigger(error_log)
  #   end
  def self.on_critical_error(&block)
    configuration.notification_callbacks[:critical_error] << block if block_given?
  end

  # Register a callback for when an error is resolved
  # @param block [Proc] The callback to execute, receives error_log as parameter
  # @example
  #   RailsErrorDashboard.on_error_resolved do |error_log|
  #     Slack.notify("Error #{error_log.id} resolved")
  #   end
  def self.on_error_resolved(&block)
    configuration.notification_callbacks[:error_resolved] << block if block_given?
  end
end
