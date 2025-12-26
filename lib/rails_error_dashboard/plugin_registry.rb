# frozen_string_literal: true

module RailsErrorDashboard
  # Registry for managing plugins
  # Provides plugin registration and event dispatching
  class PluginRegistry
    class << self
      # Get all registered plugins
      def plugins
        @plugins ||= []
      end

      # Register a plugin
      # @param plugin [Plugin] The plugin instance to register
      def register(plugin)
        unless plugin.is_a?(Plugin)
          raise ArgumentError, "Plugin must be an instance of RailsErrorDashboard::Plugin"
        end

        if plugins.any? { |p| p.name == plugin.name }
          RailsErrorDashboard::Logger.warn("Plugin '#{plugin.name}' is already registered, skipping")
          return false
        end

        plugins << plugin
        plugin.on_register
        RailsErrorDashboard::Logger.info("Registered plugin: #{plugin.name} (#{plugin.version})")
        true
      end

      # Unregister a plugin by name
      # @param plugin_name [String] The name of the plugin to unregister
      def unregister(plugin_name)
        plugins.reject! { |p| p.name == plugin_name }
      end

      # Clear all plugins (useful for testing)
      def clear
        @plugins = []
      end

      # Get a plugin by name
      # @param plugin_name [String] The name of the plugin
      # @return [Plugin, nil] The plugin instance or nil if not found
      def find(plugin_name)
        plugins.find { |p| p.name == plugin_name }
      end

      # Dispatch an event to all registered plugins
      # @param event_name [Symbol] The event name (e.g., :on_error_logged)
      # @param args [Array] Arguments to pass to the event handler
      def dispatch(event_name, *args)
        plugins.each do |plugin|
          next unless plugin.enabled?

          plugin.safe_execute(event_name, *args)
        end
      end

      # Get count of registered plugins
      def count
        plugins.size
      end

      # Check if any plugins are registered
      def any?
        plugins.any?
      end

      # Get list of plugin names
      def names
        plugins.map(&:name)
      end

      # Get plugin information for debugging
      def info
        plugins.map do |plugin|
          {
            name: plugin.name,
            version: plugin.version,
            description: plugin.description,
            enabled: plugin.enabled?
          }
        end
      end
    end
  end
end
