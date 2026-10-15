# frozen_string_literal: true

module RailsErrorDashboard
  # Registry for managing plugins
  # Provides plugin registration and event dispatching
  #
  # A plugin is host code running inside RED's own paths, so nothing it does
  # may break them: a `name` that raises (the base class raises
  # NotImplementedError, a ScriptError that `rescue => e` does not catch), an
  # `on_register` that raises, or an `enabled?` that raises is logged and
  # treated as "no", never propagated. A plugin is in the list only once
  # registration has fully succeeded.
  class PluginRegistry
    class << self
      # Get all registered plugins
      def plugins
        @plugins ||= []
      end

      # Register a plugin
      # @param plugin [Plugin] The plugin instance to register
      # @return [Boolean] true when registered, false when skipped
      # @raise [ArgumentError] not a Plugin, or no usable name
      def register(plugin)
        unless plugin.is_a?(Plugin)
          raise ArgumentError, "Plugin must be an instance of RailsErrorDashboard::Plugin"
        end

        name = name_of(plugin)
        if name.blank?
          raise ArgumentError, "Plugin #{plugin.class} must implement #name and return a non-blank String"
        end

        if plugins.any? { |p| name_of(p) == name }
          RailsErrorDashboard::Logger.warn("Plugin '#{name}' is already registered, skipping")
          return false
        end

        begin
          plugin.on_register
        rescue => e
          RailsErrorDashboard::Logger.error(
            "[RailsErrorDashboard] Plugin '#{name}' failed in on_register: #{e.class} - #{e.message}; not registered"
          )
          return false
        end

        plugins << plugin
        RailsErrorDashboard::Logger.info("Registered plugin: #{name} (#{version_of(plugin)})")
        true
      end

      # Unregister a plugin by name
      # @param plugin_name [String] The name of the plugin to unregister
      def unregister(plugin_name)
        plugins.reject! { |p| name_of(p) == plugin_name }
      end

      # Clear all plugins (useful for testing)
      def clear
        @plugins = []
      end

      # Get a plugin by name
      # @param plugin_name [String] The name of the plugin
      # @return [Plugin, nil] The plugin instance or nil if not found
      def find(plugin_name)
        plugins.find { |p| name_of(p) == plugin_name }
      end

      # Dispatch an event to all registered plugins
      # @param event_name [Symbol] The event name (e.g., :on_error_logged)
      # @param args [Array] Arguments to pass to the event handler
      def dispatch(event_name, *args)
        plugins.each do |plugin|
          next unless enabled?(plugin)

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
        plugins.map { |p| name_of(p) }
      end

      # Get plugin information for debugging
      def info
        plugins.map do |plugin|
          {
            name: name_of(plugin),
            version: version_of(plugin),
            description: (plugin.description rescue nil),
            enabled: enabled?(plugin)
          }
        end
      end

      private

      # A plugin's name, or nil when #name is missing or raises.
      def name_of(plugin)
        value = plugin.name
        value.is_a?(String) ? value : value&.to_s
      rescue StandardError, NotImplementedError
        nil
      end

      def version_of(plugin)
        plugin.version.to_s
      rescue StandardError, NotImplementedError
        "unknown"
      end

      # enabled? is host code too. A raise is logged once per dispatch and
      # read as disabled, so the other plugins still run.
      def enabled?(plugin)
        plugin.enabled? ? true : false
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Plugin '#{name_of(plugin) || plugin.class}' failed in enabled?: #{e.class} - #{e.message}; treated as disabled"
        )
        false
      end
    end
  end
end
