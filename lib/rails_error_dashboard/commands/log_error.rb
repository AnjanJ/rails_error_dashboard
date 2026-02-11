# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Log an error to the database
    # This is a write operation that creates an ErrorLog record
    class LogError
      def self.call(exception, context = {})
        # Check if async logging is enabled
        if RailsErrorDashboard.configuration.async_logging
          # For async logging, just enqueue the job
          # All filtering happens when the job runs
          call_async(exception, context)
        else
          # For sync logging, execute immediately
          new(exception, context).call
        end
      end

      # Queue error logging as a background job
      def self.call_async(exception, context = {})
        # Serialize exception data for the job
        exception_data = {
          class_name: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace
        }

        # Enqueue the async job using ActiveJob
        # The queue adapter (:sidekiq, :solid_queue, :async) is configured separately
        AsyncErrorLoggingJob.perform_later(exception_data, context)
      end

      def initialize(exception, context = {})
        @exception = exception
        @context = context
      end

      def call
        # Check if this exception should be logged (ignore list + sampling)
        return nil unless Services::ExceptionFilter.should_log?(@exception)

        error_context = ValueObjects::ErrorContext.new(@context, @context[:source])

        # Find or create application (cached lookup)
        application = find_or_create_application

        # Build error attributes
        truncated_backtrace = truncate_backtrace(@exception.backtrace)
        attributes = {
          application_id: application.id,
          error_type: @exception.class.name,
          message: @exception.message,
          backtrace: truncated_backtrace,
          user_id: error_context.user_id,
          request_url: error_context.request_url,
          request_params: error_context.request_params,
          user_agent: error_context.user_agent,
          ip_address: error_context.ip_address,
          platform: error_context.platform,
          controller_name: error_context.controller_name,
          action_name: error_context.action_name,
          occurred_at: Time.current
        }

        # Generate error hash for deduplication (including controller/action context and application)
        error_hash = Services::ErrorHashGenerator.call(
          @exception,
          controller_name: error_context.controller_name,
          action_name: error_context.action_name,
          application_id: application.id
        )

        #  Calculate backtrace signature for fuzzy matching (if column exists)
        if ErrorLog.column_names.include?("backtrace_signature")
          attributes[:backtrace_signature] = calculate_backtrace_signature_from_backtrace(truncated_backtrace)
        end

        #  Add git/release info if columns exist
        if ErrorLog.column_names.include?("git_sha")
          attributes[:git_sha] = RailsErrorDashboard.configuration.git_sha ||
                                  ENV["GIT_SHA"] ||
                                  ENV["HEROKU_SLUG_COMMIT"] ||
                                  ENV["RENDER_GIT_COMMIT"] ||
                                  detect_git_sha_from_command
        end

        if ErrorLog.column_names.include?("app_version")
          attributes[:app_version] = RailsErrorDashboard.configuration.app_version ||
                                      ENV["APP_VERSION"] ||
                                      detect_version_from_file
        end

        # Find existing error or create new one
        # This ensures accurate occurrence tracking
        error_log = ErrorLog.find_or_increment_by_hash(error_hash, attributes.merge(error_hash: error_hash))

        #  Track individual error occurrence for co-occurrence analysis (if table exists)
        if defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
          begin
            ErrorOccurrence.create(
              error_log: error_log,
              occurred_at: attributes[:occurred_at],
              user_id: attributes[:user_id],
              request_id: error_context.request_id,
              session_id: error_context.session_id
            )
          rescue => e
            RailsErrorDashboard::Logger.error("Failed to create error occurrence: #{e.message}")
          end
        end

        # Send notifications only for new errors (not increments)
        # Check if this is first occurrence or error was just created
        if error_log.occurrence_count == 1
          Services::ErrorNotificationDispatcher.call(error_log)
          # Dispatch plugin event for new error
          PluginRegistry.dispatch(:on_error_logged, error_log)
          # Trigger notification callbacks
          trigger_callbacks(error_log)
          # Emit ActiveSupport::Notifications instrumentation events
          emit_instrumentation_events(error_log)
        else
          # Dispatch plugin event for error recurrence
          PluginRegistry.dispatch(:on_error_recurred, error_log)
        end

        #  Check for baseline anomalies
        check_baseline_anomaly(error_log)

        error_log
      rescue => e
        # Don't let error logging cause more errors - fail silently
        # CRITICAL: Log but never propagate exception
        RailsErrorDashboard::Logger.error("[RailsErrorDashboard] LogError command failed: #{e.class} - #{e.message}")
        RailsErrorDashboard::Logger.error("Original exception: #{@exception.class} - #{@exception.message}") if @exception
        RailsErrorDashboard::Logger.error("Context: #{@context.inspect}") if @context
        RailsErrorDashboard::Logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace
        nil # Explicitly return nil, never raise
      end

      private

      # Find or create application for multi-app support
      def find_or_create_application
        app_name = RailsErrorDashboard.configuration.application_name ||
                   ENV["APPLICATION_NAME"] ||
                   (defined?(Rails) && Rails.application.class.module_parent_name) ||
                   "Rails Application"

        Application.find_or_create_by_name(app_name)
      rescue => e
        RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Failed to find/create application: #{e.message}")
        # Fallback: try to find any application or create default
        Application.first || Application.create!(name: "Default Application")
      end

      # Trigger notification callbacks for error logging
      def trigger_callbacks(error_log)
        # Trigger general error_logged callbacks
        RailsErrorDashboard.configuration.notification_callbacks[:error_logged].each do |callback|
          callback.call(error_log)
        rescue => e
          RailsErrorDashboard::Logger.error("Error in error_logged callback: #{e.message}")
        end

        # Trigger critical_error callbacks if this is a critical error
        if error_log.critical?
          RailsErrorDashboard.configuration.notification_callbacks[:critical_error].each do |callback|
            callback.call(error_log)
          rescue => e
            RailsErrorDashboard::Logger.error("Error in critical_error callback: #{e.message}")
          end
        end
      end

      # Emit ActiveSupport::Notifications instrumentation events
      def emit_instrumentation_events(error_log)
        # Payload for instrumentation subscribers
        payload = {
          error_log: error_log,
          error_id: error_log.id,
          error_type: error_log.error_type,
          message: error_log.message,
          severity: error_log.severity,
          platform: error_log.platform,
          occurred_at: error_log.occurred_at
        }

        # Emit general error_logged event
        ActiveSupport::Notifications.instrument("error_logged.rails_error_dashboard", payload)

        # Emit critical_error event if this is a critical error
        if error_log.critical?
          ActiveSupport::Notifications.instrument("critical_error.rails_error_dashboard", payload)
        end
      end


      # Truncate backtrace to configured maximum lines
      # This reduces database storage and improves performance
      def truncate_backtrace(backtrace)
        return nil if backtrace.nil?

        max_lines = RailsErrorDashboard.configuration.max_backtrace_lines

        # Limit backtrace to max_lines
        limited_backtrace = backtrace.first(max_lines)

        # Join into string
        result = limited_backtrace.join("\n")

        # Add truncation notice if we cut lines
        if backtrace.length > max_lines
          truncation_notice = "... (#{backtrace.length - max_lines} more lines truncated)"
          result = result.empty? ? truncation_notice : result + "\n" + truncation_notice
        end

        result
      end

      #  Calculate backtrace signature from backtrace string/array
      # This matches the algorithm in ErrorLog#calculate_backtrace_signature
      def calculate_backtrace_signature_from_backtrace(backtrace)
        return nil if backtrace.blank?

        lines = backtrace.is_a?(String) ? backtrace.split("\n") : backtrace
        frames = lines.first(20).map do |line|
          # Extract file path and method name, ignore line numbers
          if line =~ %r{([^/]+\.rb):.*?in `(.+)'$}
            "#{Regexp.last_match(1)}:#{Regexp.last_match(2)}"
          elsif line =~ %r{([^/]+\.rb)}
            Regexp.last_match(1)
          end
        end.compact.uniq

        return nil if frames.empty?

        # Create signature from sorted file paths (order-independent)
        file_paths = frames.map { |frame| frame.split(":").first }.sort
        Digest::SHA256.hexdigest(file_paths.join("|"))[0..15]
      end

      #  Check if error exceeds baseline and send alert if needed
      def check_baseline_anomaly(error_log)
        config = RailsErrorDashboard.configuration

        # Return early if baseline alerts are disabled
        return unless config.enable_baseline_alerts
        return unless defined?(Queries::BaselineStats)
        return unless defined?(BaselineAlertJob)

        # Get baseline anomaly info
        anomaly = error_log.baseline_anomaly(sensitivity: config.baseline_alert_threshold_std_devs)

        # Return if no anomaly detected
        return unless anomaly[:anomaly]

        # Check if severity level should trigger alert
        return unless config.baseline_alert_severities.include?(anomaly[:level])

        # Enqueue alert job (which will handle throttling)
        BaselineAlertJob.perform_later(error_log.id, anomaly)

        RailsErrorDashboard::Logger.info(
          "Baseline alert queued for #{error_log.error_type} on #{error_log.platform}: " \
          "#{anomaly[:level]} (#{anomaly[:std_devs_above]&.round(1)}σ above baseline)"
        )
      rescue => e
        # Don't let baseline alerting cause errors
        RailsErrorDashboard::Logger.error("Failed to check baseline anomaly: #{e.message}")
      end

      # Detect git SHA from git command (fallback)
      def detect_git_sha_from_command
        return nil unless File.exist?(Rails.root.join(".git"))
        `git rev-parse --short HEAD 2>/dev/null`.strip.presence
      rescue => e
        RailsErrorDashboard::Logger.debug("Could not detect git SHA: #{e.message}")
        nil
      end

      # Detect app version from VERSION file (fallback)
      def detect_version_from_file
        version_file = Rails.root.join("VERSION")
        return File.read(version_file).strip if File.exist?(version_file)
        nil
      rescue => e
        RailsErrorDashboard::Logger.debug("Could not detect version: #{e.message}")
        nil
      end
    end
  end
end
