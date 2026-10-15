# frozen_string_literal: true

module RailsErrorDashboard
  # Base class for creating plugins
  # Plugins can hook into error lifecycle events and extend functionality
  #
  # Example plugin:
  #
  #   class MyNotificationPlugin < RailsErrorDashboard::Plugin
  #     def name
  #       "My Custom Notifier"
  #     end
  #
  #     def on_error_logged(error_log)
  #       # Send notification to custom service
  #       MyService.notify(error_log)
  #     end
  #   end
  #
  #   # Register the plugin
  #   RailsErrorDashboard.register_plugin(MyNotificationPlugin.new)
  #
  class Plugin
    # Plugin name (must be implemented by subclass)
    def name
      raise NotImplementedError, "Plugin must implement #name"
    end

    # Plugin description (optional)
    def description
      "No description provided"
    end

    # Plugin version (optional)
    def version
      "1.0.0"
    end

    # Called when plugin is registered
    # Use this for initialization logic
    def on_register
      # Override in subclass if needed
    end

    # Called when a new error is logged (first occurrence)
    # @param error_log [ErrorLog] The newly created error log
    def on_error_logged(error_log)
      # Override in subclass to handle event
    end

    # Called when an existing error recurs (subsequent occurrences)
    # @param error_log [ErrorLog] The updated error log
    def on_error_recurred(error_log)
      # Override in subclass to handle event
    end

    # Called when a resolved error occurs again and is reopened
    # @param error_log [ErrorLog] The reopened error log
    def on_error_reopened(error_log)
      # Override in subclass to handle event
    end

    # Called when an error is resolved
    # @param error_log [ErrorLog] The resolved error log
    def on_error_resolved(error_log)
      # Override in subclass to handle event
    end

    # Called when an error is muted
    # @param error_log [ErrorLog] The muted error log
    def on_error_muted(error_log)
      # Override in subclass to handle event
    end

    # Called when an error is unmuted
    # @param error_log [ErrorLog] The unmuted error log
    def on_error_unmuted(error_log)
      # Override in subclass to handle event
    end

    # Called when errors are batch muted
    # @param error_logs [Array<ErrorLog>] The muted error logs
    def on_errors_batch_muted(error_logs)
      # Override in subclass to handle event
    end

    # Called when errors are batch unmuted
    # @param error_logs [Array<ErrorLog>] The unmuted error logs
    def on_errors_batch_unmuted(error_logs)
      # Override in subclass to handle event
    end

    # Called when errors are batch resolved
    # @param error_logs [Array<ErrorLog>] The resolved error logs
    def on_errors_batch_resolved(error_logs)
      # Override in subclass to handle event
    end

    # Called when errors are batch deleted
    # @param error_ids [Array<Integer>] The IDs of deleted errors
    def on_errors_batch_deleted(error_ids)
      # Override in subclass to handle event
    end

    # Called when an error is viewed in the dashboard
    # @param error_log [ErrorLog] The viewed error log
    def on_error_viewed(error_log)
      # Override in subclass to handle event
    end

    # Helper method to check if plugin is enabled
    # Override this to add conditional logic
    def enabled?
      true
    end

    # Helper method to safely execute plugin hooks
    # CRITICAL: Prevents plugin errors from breaking the main application
    def safe_execute(method_name, *args)
      return unless enabled?

      send(method_name, *args)
    rescue => e
      # Log plugin failures but never propagate - plugins must not break the app.
      # name and version are plugin code too, so the log line must not depend
      # on them answering.
      RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Plugin '#{safe_label}' failed in #{method_name}: #{e.class} - #{e.message}")
      RailsErrorDashboard::Logger.error("Plugin version: #{safe_version}")
      RailsErrorDashboard::Logger.error(e.backtrace&.first(10)&.join("\n")) if e.backtrace
      nil # Explicitly return nil, never raise
    end

    private

    def safe_label
      name.to_s
    rescue StandardError, NotImplementedError
      self.class.name
    end

    def safe_version
      version.to_s
    rescue StandardError, NotImplementedError
      "unknown"
    end
  end
end
