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
        # Check if this exception should be ignored
        return nil if should_ignore_exception?(@exception)

        # Check sampling rate for non-critical errors
        # Critical errors are ALWAYS logged regardless of sampling
        return nil if should_skip_due_to_sampling?(@exception)

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
        error_hash = generate_error_hash(@exception, error_context.controller_name, error_context.action_name, application.id)

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
          send_notifications(error_log)
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

      # Check if error should be skipped due to sampling rate
      # Critical errors are ALWAYS logged, sampling only applies to non-critical errors
      def should_skip_due_to_sampling?(exception)
        sampling_rate = RailsErrorDashboard.configuration.sampling_rate

        # If sampling is 100% (1.0) or higher, log everything
        return false if sampling_rate >= 1.0

        # Always log critical errors regardless of sampling rate
        # Check this BEFORE checking for 0% sampling
        return false if is_critical_error?(exception)

        # If sampling is 0% or negative, skip all non-critical errors
        return true if sampling_rate <= 0.0

        # For non-critical errors, use probabilistic sampling
        # rand returns 0.0 to 1.0, so if sampling_rate is 0.1 (10%),
        # we skip 90% of errors (when rand > 0.1)
        rand > sampling_rate
      end

      # Check if exception is a critical error type
      def is_critical_error?(exception)
        exception_class_name = exception.class.name
        RailsErrorDashboard::ErrorLog::CRITICAL_ERROR_TYPES.include?(exception_class_name)
      end

      # Check if exception should be ignored based on configuration
      # Supports both string class names and regex patterns
      def should_ignore_exception?(exception)
        ignored_exceptions = RailsErrorDashboard.configuration.ignored_exceptions
        return false if ignored_exceptions.blank?

        exception_class_name = exception.class.name

        ignored_exceptions.any? do |ignored|
          case ignored
          when String
            # Exact class name match (supports inheritance)
            exception.is_a?(ignored.constantize)
          when Regexp
            # Regex pattern match on class name
            exception_class_name.match?(ignored)
          else
            false
          end
        rescue NameError
          # Handle invalid class names in configuration
          RailsErrorDashboard::Logger.warn("Invalid ignored exception class: #{ignored}")
          false
        end
      end

      # Generate consistent hash for error deduplication
      # Same hash = same error type
      # Note: This is also defined in ErrorLog model for backward compatibility
      def generate_error_hash(exception, controller_name = nil, action_name = nil, application_id = nil)
        # Hash components:
        # 1. Error class (NoMethodError, ArgumentError, etc.)
        # 2. Normalized message (replace numbers, quoted strings)
        # 3. First stack frame file (ignore line numbers)
        # 4. Controller name (for context-aware grouping)
        # 5. Action name (for context-aware grouping)
        # 6. Application ID (for per-app deduplication)

        normalized_message = exception.message
          &.gsub(/\d+/, "N")                    # Replace numbers: "User 123" -> "User N"
          &.gsub(/"[^"]*"/, '""')               # Replace quoted strings: "foo" -> ""
          &.gsub(/'[^']*'/, "''")               # Replace single quoted strings
          &.gsub(/0x[0-9a-f]+/i, "0xHEX")       # Replace hex addresses
          &.gsub(/#<[^>]+>/, "#<OBJ>")          # Replace object inspections

        # Get first meaningful stack frame (skip gems, focus on app code)
        first_app_frame = exception.backtrace&.find { |frame|
          # Look for app code, not gems
          frame.include?("/app/") || frame.include?("/lib/") || !frame.include?("/gems/")
        }

        # Extract just the file path, not line number
        file_path = first_app_frame&.split(":")&.first

        # Generate hash including controller/action/application for better grouping
        digest_input = [
          exception.class.name,
          normalized_message,
          file_path,
          controller_name,      # Context: which controller
          action_name,          # Context: which action
          application_id.to_s   # Context: which application (for per-app deduplication)
        ].compact.join("|")

        Digest::SHA256.hexdigest(digest_input)[0..15]
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

      def send_notifications(error_log)
        config = RailsErrorDashboard.configuration

        # Send Slack notification
        if config.enable_slack_notifications && config.slack_webhook_url.present?
          SlackErrorNotificationJob.perform_later(error_log.id)
        end

        # Send email notification
        if config.enable_email_notifications && config.notification_email_recipients.present?
          EmailErrorNotificationJob.perform_later(error_log.id)
        end

        # Send Discord notification
        if config.enable_discord_notifications && config.discord_webhook_url.present?
          DiscordErrorNotificationJob.perform_later(error_log.id)
        end

        # Send PagerDuty notification (critical errors only)
        if config.enable_pagerduty_notifications && config.pagerduty_integration_key.present?
          PagerdutyErrorNotificationJob.perform_later(error_log.id)
        end

        # Send webhook notifications
        if config.enable_webhook_notifications && config.webhook_urls.present?
          WebhookErrorNotificationJob.perform_later(error_log.id)
        end
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
