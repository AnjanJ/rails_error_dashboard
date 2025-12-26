# frozen_string_literal: true

module RailsErrorDashboard
  # Internal logger wrapper for Rails Error Dashboard
  #
  # By default, all logging is SILENT to keep production logs clean.
  # Users can opt-in to verbose logging for debugging.
  #
  # @example Enable logging for debugging
  #   RailsErrorDashboard.configure do |config|
  #     config.enable_internal_logging = true
  #     config.log_level = :debug
  #   end
  #
  # @example Production troubleshooting (errors only)
  #   RailsErrorDashboard.configure do |config|
  #     config.enable_internal_logging = true
  #     config.log_level = :error
  #   end
  module Logger
    LOG_LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
      silent: 4
    }.freeze

    class << self
      # Log debug message (only if internal logging enabled)
      #
      # @param message [String] The message to log
      # @example
      #   RailsErrorDashboard::Logger.debug("Processing error #123")
      def debug(message)
        return unless logging_enabled?
        return unless log_level_enabled?(:debug)

        Rails.logger.debug(formatted_message(message))
      end

      # Log info message (only if internal logging enabled)
      #
      # @param message [String] The message to log
      # @example
      #   RailsErrorDashboard::Logger.info("Registered plugin: MyPlugin")
      def info(message)
        return unless logging_enabled?
        return unless log_level_enabled?(:info)

        Rails.logger.info(formatted_message(message))
      end

      # Log warning message (only if internal logging enabled)
      #
      # @param message [String] The message to log
      # @example
      #   RailsErrorDashboard::Logger.warn("Plugin already registered")
      def warn(message)
        return unless logging_enabled?
        return unless log_level_enabled?(:warn)

        Rails.logger.warn(formatted_message(message))
      end

      # Log error message
      # Errors are logged by default unless log_level is :silent
      #
      # @param message [String] The message to log
      # @example
      #   RailsErrorDashboard::Logger.error("Failed to save error log")
      def error(message)
        return unless log_level_enabled?(:error)

        Rails.logger.error(formatted_message(message))
      end

      private

      # Check if internal logging is enabled
      #
      # @return [Boolean]
      def logging_enabled?
        RailsErrorDashboard.configuration.enable_internal_logging
      end

      # Check if the given log level is enabled
      #
      # @param level [Symbol] The log level to check (:debug, :info, :warn, :error)
      # @return [Boolean]
      def log_level_enabled?(level)
        config_level = RailsErrorDashboard.configuration.log_level || :silent
        LOG_LEVELS[level] >= LOG_LEVELS[config_level]
      end

      # Format message with gem prefix
      #
      # @param message [String] The message to format
      # @return [String] Formatted message with prefix
      def formatted_message(message)
        "[RailsErrorDashboard] #{message}"
      end
    end
  end
end
