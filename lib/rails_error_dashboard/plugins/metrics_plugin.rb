# frozen_string_literal: true

module RailsErrorDashboard
  module Plugins
    # Example plugin: Metrics tracking
    # Tracks error counts and sends to metrics service (e.g., StatsD, Datadog)
    #
    # Usage:
    #   RailsErrorDashboard.register_plugin(
    #     RailsErrorDashboard::Plugins::MetricsPlugin.new
    #   )
    #
    class MetricsPlugin < Plugin
      def name
        "Metrics Tracker"
      end

      def description
        "Tracks error metrics and sends to monitoring service"
      end

      def version
        "1.0.0"
      end

      def on_error_logged(error_log)
        increment_counter("errors.new", error_log)
        increment_counter("errors.by_type.#{sanitize_metric_name(error_log.error_type)}", error_log)
        increment_counter("errors.by_platform.#{error_log.platform || 'unknown'}", error_log)
      end

      def on_error_recurred(error_log)
        increment_counter("errors.recurred", error_log)
        increment_counter("errors.occurrence.#{error_log.id}", error_log)
      end

      def on_error_resolved(error_log)
        increment_counter("errors.resolved", error_log)
      end

      def on_errors_batch_resolved(error_logs)
        increment_counter("errors.batch_resolved", count: error_logs.size)
      end

      def on_errors_batch_deleted(error_ids)
        increment_counter("errors.batch_deleted", count: error_ids.size)
      end

      private

      def increment_counter(metric_name, data)
        # Example: Send to StatsD
        # StatsD.increment(metric_name, tags: metric_tags(data))

        # Example: Send to Datadog
        # Datadog::Statsd.increment(metric_name, tags: metric_tags(data))

        # For demonstration, just log
        RailsErrorDashboard::Logger.info("Metrics: #{metric_name} - #{data.is_a?(Hash) ? data : data.class.name}")
      end

      def metric_tags(data)
        return [] unless data.respond_to?(:platform)

        [
          "platform:#{data.platform || 'unknown'}",
          "severity:#{data.severity}"
        ]
      end

      def sanitize_metric_name(name)
        name.gsub("::", ".").downcase
      end
    end
  end
end
