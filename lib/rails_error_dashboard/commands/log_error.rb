# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Log an error to the database
    # This is a write operation that creates an ErrorLog record
    class LogError
      # Raised internally when perform_later did not reach the queue, so the
      # one rescue below covers both failure shapes. Never escapes this class.
      class EnqueueFailed < StandardError; end

      # The error store is down right now and may be up in a moment. Worth
      # another attempt from a background worker; indistinguishable from any
      # other failure on a user's request, where nothing is ever re-raised.
      RETRYABLE_STORE_ERRORS = [
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::StatementInvalid,
        ActiveRecord::LockWaitTimeout,
        ActiveRecord::Deadlocked
      ].freeze

      def self.call(exception, context = {})
        # Filter FIRST (ignore list + static sampling) so ignored exceptions
        # never count toward storm state. _pre_filtered prevents the sync path
        # from re-rolling the sampling dice (rate would square otherwise).
        # The filter + gate run inside this method's rescue: nothing in the
        # capture path may ever raise into the host app.
        begin
          unless Services::ExceptionFilter.should_log?(exception)
            # Preserve the OTel contract: filtered captures still emit a span
            # tagged filtered=true (no-op when OTel export is disabled).
            Integrations::Tracer.in_span(
              "capture_error",
              kind: :capture,
              attributes: build_capture_span_attributes(exception, was_async: false)
            ) do |span|
              span&.set_attribute("rails_error_dashboard.filtered", true)
            end
            return nil
          end
          context = context.merge(_pre_filtered: true)

          # Storm protection gate — BEFORE the async branch, because with
          # SolidQueue the enqueue itself is a DB write. :count_only events are
          # tallied in memory and reconciled by StormFlushJob; nothing else
          # happens for them (that's the point).
          storm_decision = Services::StormProtection::Gate.admit!(exception, context)
          return nil if storm_decision == :count_only
          context = context.merge(_storm_decision: storm_decision) if storm_decision == :lite
        rescue => e
          RailsErrorDashboard::Logger.error(
            "[RailsErrorDashboard] Capture pre-checks failed: #{e.class} - #{e.message}"
          )
          # Fall through and attempt full capture — fail open, never raise
        end

        if RailsErrorDashboard.configuration.async_logging
          # For async logging, just enqueue the job
          call_async(exception, context)
        else
          # For sync logging, execute immediately
          new(exception, context).call
        end
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] LogError.call failed: #{e.class} - #{e.message}"
        )
        nil
      end

      # :lite captures shed context (breadcrumbs/health/locals/ivars) — the
      # storm shedding ladder's first economy. Symbol or string key: the
      # async job round-trips context through the queue serializer.
      def self.storm_lite?(context)
        context[:_storm_decision].to_s == "lite"
      end

      # Build the base OTel span attributes available before any work happens.
      # Kept as a module-level helper so both sync and async paths can call it.
      # @return [Hash<String, Object>]
      def self.build_capture_span_attributes(exception, was_async:)
        msg = exception.message.to_s
        {
          "error.type" => exception.class.name,
          "error.message" => msg.length > 200 ? "#{msg[0, 200]}…" : msg,
          "rails_error_dashboard.environment" => (defined?(Rails) && Rails.env.to_s) || "unknown",
          "rails_error_dashboard.was_async" => was_async
        }
      rescue StandardError
        { "error.type" => "unknown", "rails_error_dashboard.was_async" => was_async }
      end

      # Queue error logging as a background job
      def self.call_async(exception, context = {})
        # Serialize exception data for the job
        # Grouping identity is computed from the RAW message, BEFORE redaction
        # below. ErrorHashGenerator hashes a 500-char prefix of the unredacted
        # message, so redacting first would silently re-group every error whose
        # message contains a filtered key: "password=hunter2" and
        # "password=[FILTERED]" are different fingerprints.
        #
        # application_id is deliberately absent. Resolving it means
        # Application.find_or_create_by_name -- a DB write -- and this runs on
        # the request thread, where the gem promises no I/O. The worker
        # completes the hash with the application resolved, exactly as
        # FlushStormCounts#canonical_hash does for storm counts.
        identity_parts = capture_identity_parts(exception, context)

        # Scrub BEFORE anything is serialized: ActiveJob JSON-encodes the
        # payload on this (the request) thread, and an invalid byte in the
        # message, a backtrace line or the context would raise right here. The
        # identity above is still taken from the raw exception, exactly as the
        # sync path takes it, so grouping is unchanged.
        context = Services::EncodingSanitizer.scrub_deep(context)
        exception_data = Services::EncodingSanitizer.scrub_deep(
          class_name: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace,
          cause_chain: serialize_cause_chain(exception)
        )

        # Redact BEFORE the payload crosses the queue boundary. Until now the
        # filter ran only just before the INSERT, so a durable adapter
        # (Sidekiq/Redis, Solid Queue) persisted the raw secret in its own
        # store, its backups, and any job-argument logging -- even though the
        # error row itself was correctly redacted.
        #
        # Breadcrumbs, locals and instance variables are already filtered by
        # their own collectors (BreadcrumbCollector.filter_sensitive,
        # VariableSerializer.filter_serialized) before they are put in the
        # context above, so this covers the rest: message, cause chain, request
        # params and request URL -- the four keys filter_attributes touches.
        exception_data, context = redact_async_payload(exception_data, context)
        context = context.merge(_identity: identity_parts) if identity_parts

        # Storm shedding: :lite captures skip ALL pre-enqueue context harvest —
        # this is request-thread CPU, the most valuable thing to shed.
        lite = storm_lite?(context)

        # Harvest breadcrumbs NOW (before job dispatch — different thread won't have them)
        if !lite && RailsErrorDashboard.configuration.enable_breadcrumbs
          context = context.merge(_serialized_breadcrumbs: Services::BreadcrumbCollector.harvest)
        end

        # Capture system health NOW (metrics are time-sensitive, different thread = different state)
        if !lite && RailsErrorDashboard.configuration.enable_system_health
          context = context.merge(_serialized_system_health: Services::SystemHealthSnapshot.capture)
        end

        # Capture local variables NOW (TracePoint attaches to exception, must extract before job dispatch)
        if !lite && RailsErrorDashboard.configuration.enable_local_variables
          begin
            raw_locals = Services::LocalVariableCapturer.extract(exception)
            if raw_locals.is_a?(Hash) && raw_locals.any?
              context = context.merge(_serialized_local_variables: Services::VariableSerializer.call(raw_locals))
            end
          rescue => e
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Async local variable serialization failed: #{e.message}")
          end
        end

        # Capture instance variables NOW (same reason — attached to exception object)
        if !lite && RailsErrorDashboard.configuration.enable_instance_variables
          begin
            raw_ivars = Services::LocalVariableCapturer.extract_instance_vars(exception)
            if raw_ivars.is_a?(Hash) && raw_ivars.any?
              context = context.merge(_serialized_instance_variables: Services::VariableSerializer.call(
                raw_ivars,
                max_count: RailsErrorDashboard.configuration.instance_variable_max_count,
                additional_filter_patterns: RailsErrorDashboard.configuration.instance_variable_filter_patterns
              ))
            end
          rescue => e
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Async instance variable serialization failed: #{e.message}")
          end
        end

        # Enqueue the async job using ActiveJob
        # The queue adapter (:sidekiq, :solid_queue, :async) is configured separately
        begin
          # OTel: emit a capture span around the enqueue itself. The real capture
          # work runs in the job (which starts its own root span via .new(...).call).
          # For the async path the span here measures *enqueue latency only* — used
          # to detect queue-adapter backpressure or Redis slowness.
          Integrations::Tracer.in_span(
            "capture_error",
            kind: :capture,
            attributes: build_capture_span_attributes(exception, was_async: true)
          ) do |_span|
            job = AsyncErrorLoggingJob.perform_later(exception_data, context)

            # A raise is not the only way a handoff fails. From Rails 7.2
            # perform_later swallows ActiveJob::EnqueueError and returns false
            # (an aborting enqueue callback does the same), so without this
            # check the capture is dropped silently: no queued job, no row.
            # The storm gate has always checked this; ordinary capture did not.
            unless ApplicationJob.enqueued?(job)
              raise EnqueueFailed, ApplicationJob.enqueue_failure_reason(job)
            end
          end
        rescue => e
          # Queue adapter failed (e.g., Redis down for Sidekiq), or the job
          # never reached the queue. Fall back to sync logging so the error is
          # still captured. Without this rescue, the exception propagates back
          # to ErrorReporter, which re-reports it via Rails.error.report →
          # infinite recursion (issue #114).
          RailsErrorDashboard::Logger.error(
            "[RailsErrorDashboard] Async enqueue failed (#{e.class}: #{e.message}), falling back to sync logging"
          )
          new(exception, context).call
        end
      end

      # The opaque half of the canonical fingerprint, computed from the RAW
      # exception before the payload is redacted for the queue.
      #
      # This is a digest, not the identity parts themselves: an earlier version
      # shipped `normalized_message` and put the very secret the redaction had
      # just removed straight back on the queue. normalize_message replaces
      # hex, digits and quoted strings -- it has no notion of secrets.
      #
      # A custom fingerprint lambda already yields a complete, message-free
      # value, so it is passed through unchanged.
      def self.capture_identity_parts(exception, context)
        custom = Services::ErrorHashGenerator.send(:try_custom_fingerprint, exception, context)
        return custom if custom

        Services::ErrorHashGenerator.opaque_identity(
          error_class: exception.class.name,
          normalized_message: Services::ErrorHashGenerator.normalize_message(exception.message),
          frames: Services::ErrorHashGenerator.extract_app_frame_from_locations(exception) ||
                  Services::ErrorHashGenerator.extract_app_frame(exception.backtrace),
          controller_name: context[:controller_name]&.to_s,
          action_name: context[:action_name]&.to_s
        )
      rescue => e
        # No identity parts simply means the worker recomputes the hash from
        # the (redacted) payload, which is the pre-existing behaviour.
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] capture_identity_parts failed: #{e.class} - #{e.message}"
        )
        nil
      end

      # Apply the storage filter to everything secret-bearing that crosses the
      # queue, reusing SensitiveDataFilter so the queue and the database are
      # redacted by ONE policy rather than two that can drift.
      def self.redact_async_payload(exception_data, context)
        return [ exception_data, context ] unless RailsErrorDashboard.configuration.filter_sensitive_data

        filtered = Services::SensitiveDataFilter.filter_attributes(
          message: exception_data[:message],
          request_params: context[:request_params],
          request_url: context[:request_url],
          exception_cause: exception_data[:cause_chain]&.to_json
        )

        exception_data = exception_data.merge(message: filtered[:message])
        if exception_data[:cause_chain] && filtered[:exception_cause]
          begin
            exception_data = exception_data.merge(
              cause_chain: JSON.parse(filtered[:exception_cause], symbolize_names: true)
            )
          rescue JSON::ParserError
            # Keep the filtered-but-unparsed chain out of the payload entirely
            # rather than shipping the raw one.
            exception_data = exception_data.merge(cause_chain: nil)
          end
        end

        context = context.merge(request_params: filtered[:request_params]) if context.key?(:request_params)
        context = context.merge(request_url: filtered[:request_url]) if context.key?(:request_url)

        [ exception_data, context ]
      rescue => e
        # Never fail a capture over redaction. Fall back to the previous
        # behaviour: the row itself is still filtered before the INSERT.
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Async payload redaction failed: #{e.class} - #{e.message}"
        )
        [ exception_data, context ]
      end

      # Serialize cause chain for async job serialization
      # Returns an array of hashes (not JSON string) for ActiveJob compatibility
      def self.serialize_cause_chain(exception)
        return nil unless exception.respond_to?(:cause) && exception.cause

        chain = []
        current = exception.cause
        seen = Set.new
        depth = 0

        while current && depth < 5
          break if seen.include?(current.object_id)
          seen.add(current.object_id)

          chain << {
            class_name: current.class.name,
            message: current.message&.to_s,
            backtrace: current.backtrace&.first(20)&.map { |line| Services::BacktraceProcessor.shorten_gem_path(Services::EncodingSanitizer.scrub(line)) }
          }

          current = current.respond_to?(:cause) ? current.cause : nil
          depth += 1
        end

        chain.empty? ? nil : chain
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Cause chain serialization failed: #{e.message}")
        nil
      end
      private_class_method :serialize_cause_chain

      # @param exception [Exception] the exception to capture
      # @param context [Hash] request/job context
      # @param worker [Boolean] true when a background job is the caller.
      #   The capture path's blanket rescue exists so a failing capture can
      #   never break a user's request (safety rule 1). A worker has the
      #   opposite obligation: if the error store was unreachable, the job did
      #   NOT deliver the capture, and saying otherwise discards the payload.
      #   In worker mode an unreachable-store failure is re-raised so Active
      #   Job can retry it; every other failure is still swallowed.
      def initialize(exception, context = {}, worker: false)
        @exception = exception
        # Invalid bytes anywhere in the context would raise as soon as it is
        # JSON-encoded (ErrorContext does that in its constructor). A clean
        # context costs one scan and its strings come back as the same objects.
        @context = Services::EncodingSanitizer.scrub_deep(context)
        @worker = worker
      end

      def call
        # OTel: parent capture span. Wraps the entire sync capture path so
        # operators can audit how long error capture takes from their existing
        # tracing pipeline. Child spans (breadcrumbs, health, notifications)
        # nest under this one automatically via OTel context propagation.
        #
        # The span lives INSIDE the rescue clause — if span setup itself fails,
        # the Tracer runs this block once with a no-op span, and anything that
        # still escapes is caught by the outer rescue below. Defense in depth.
        # When this block raises, the façade records the exception on the span
        # and re-raises it exactly once; it never re-runs the block.
        Integrations::Tracer.in_span(
          "capture_error",
          kind: :capture,
          attributes: self.class.build_capture_span_attributes(@exception, was_async: false)
        ) do |span|
        # Check if this exception should be logged (ignore list + sampling).
        # Skipped when self.call already filtered (re-rolling the sampling
        # dice here would square the effective rate).
        if !@context[:_pre_filtered] && !Services::ExceptionFilter.should_log?(@exception)
          span&.set_attribute("rails_error_dashboard.filtered", true)
          next nil
        end

        # Storm shedding: :lite captures keep the error + occurrence row but
        # shed context payloads (breadcrumbs/health/locals/ivars).
        storm_lite = self.class.storm_lite?(@context)
        span&.set_attribute("rails_error_dashboard.storm_degraded", true) if storm_lite

        error_context = ValueObjects::ErrorContext.new(@context, @context[:source])

        # Find or create application (cached lookup)
        application = find_or_create_application
        span&.set_attribute("rails_error_dashboard.application", application.name.to_s) if application.respond_to?(:name)

        # Build error attributes
        truncated_backtrace = Services::BacktraceProcessor.truncate(@exception.backtrace)
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

        # Enriched request context (if columns exist)
        enrich_with_request_context(attributes, error_context)

        # Extract exception cause chain (if column exists)
        if ErrorLog.column_names.include?("exception_cause")
          cause_json = Services::CauseChainExtractor.call(@exception)
          # Fall back to pre-serialized cause chain from async job context
          cause_json ||= build_cause_json_from_context
          attributes[:exception_cause] = cause_json
        end

        # Generate error hash for deduplication (including controller/action context and application)
        #
        # On the async path the identity was captured from the RAW exception
        # before the payload was redacted for the queue; completing it here
        # with application_id keeps grouping identical to the sync path, where
        # the hash is taken before filter_attributes runs.
        error_hash = canonical_hash_from_identity(application) ||
                     Services::ErrorHashGenerator.call(
                       @exception,
                       controller_name: error_context.controller_name,
                       action_name: error_context.action_name,
                       application_id: application.id,
                       context: @context
                     )

        #  Calculate backtrace signature for fuzzy matching (if column exists)
        if ErrorLog.column_names.include?("backtrace_signature")
          attributes[:backtrace_signature] = Services::BacktraceProcessor.calculate_signature(
            truncated_backtrace,
            locations: @exception.backtrace_locations
          )
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

        # Add environment snapshot (if column exists)
        if ErrorLog.column_names.include?("environment_info")
          attributes[:environment_info] = Services::EnvironmentSnapshot.snapshot.to_json
        end

        # Environment awareness (if column exists). context wins so a sender
        # elsewhere can attribute an event to its own environment.
        if ErrorLog.column_names.include?("environment")
          attributes[:environment] = resolve_environment
        end

        # Neutralise invalid bytes BEFORE filtering: the filter runs regexes,
        # which raise on an invalid string, and PostgreSQL rejects the INSERT.
        attributes = Services::EncodingSanitizer.scrub_deep(attributes)

        # Apply sensitive data filtering (on by default)
        attributes = Services::SensitiveDataFilter.filter_attributes(attributes)

        # Fit string metadata to its columns (after hashing, before writing)
        attributes = ErrorLog.clamp_string_attributes(attributes)

        # Harvest breadcrumbs (if enabled and column exists)
        if !storm_lite && ErrorLog.column_names.include?("breadcrumbs") && RailsErrorDashboard.configuration.enable_breadcrumbs
          # Sync path: harvest from current thread
          raw_breadcrumbs = Services::BreadcrumbCollector.harvest

          # Async path fallback: use pre-serialized breadcrumbs from call_async context
          if raw_breadcrumbs.empty?
            serialized = @context[:_serialized_breadcrumbs]
            raw_breadcrumbs = serialized if serialized.is_a?(Array)
          end

          if raw_breadcrumbs.is_a?(Array) && raw_breadcrumbs.any?
            filtered = Services::BreadcrumbCollector.filter_sensitive(raw_breadcrumbs)
            attributes[:breadcrumbs] = Services::EncodingSanitizer.scrub_deep(filtered).to_json
          end
        end

        # Capture system health snapshot (if enabled and column exists)
        if !storm_lite && ErrorLog.column_names.include?("system_health") && RailsErrorDashboard.configuration.enable_system_health
          health_data = @context[:_serialized_system_health] || Services::SystemHealthSnapshot.capture
          attributes[:system_health] = Services::EncodingSanitizer.scrub_deep(health_data).to_json
        end

        # Capture local variables (if enabled and column exists)
        if !storm_lite && ErrorLog.column_names.include?("local_variables") && RailsErrorDashboard.configuration.enable_local_variables
          begin
            # Sync path: extract from exception ivar
            raw_locals = Services::LocalVariableCapturer.extract(@exception)
            # Async path fallback: use pre-serialized locals from call_async context
            raw_locals ||= @context[:_serialized_local_variables]
            if raw_locals.is_a?(Hash) && raw_locals.any?
              serialized = raw_locals == @context[:_serialized_local_variables] ? raw_locals : Services::VariableSerializer.call(raw_locals)
              attributes[:local_variables] = Services::EncodingSanitizer.scrub_deep(serialized).to_json
            end
          rescue => e
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Local variable serialization failed: #{e.message}")
          end
        end

        # Capture instance variables (if enabled and column exists)
        if !storm_lite && ErrorLog.column_names.include?("instance_variables") && RailsErrorDashboard.configuration.enable_instance_variables
          begin
            # Sync path: extract from exception ivar
            raw_ivars = Services::LocalVariableCapturer.extract_instance_vars(@exception)
            # Async path fallback: use pre-serialized ivars from call_async context
            raw_ivars ||= @context[:_serialized_instance_variables]
            if raw_ivars.is_a?(Hash) && raw_ivars.any?
              serialized = if raw_ivars == @context[:_serialized_instance_variables]
                raw_ivars
              else
                Services::VariableSerializer.call(
                  raw_ivars,
                  max_count: RailsErrorDashboard.configuration.instance_variable_max_count,
                  additional_filter_patterns: RailsErrorDashboard.configuration.instance_variable_filter_patterns
                )
              end
              attributes[:instance_variables] = Services::EncodingSanitizer.scrub_deep(serialized).to_json
            end
          rescue => e
            RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Instance variable serialization failed: #{e.message}")
          end
        end

        # Find existing error or create new one
        # This ensures accurate occurrence tracking.
        #
        # _context_fidelity travels with the attributes so the grouping command
        # can tell a full capture from a shed one. A :lite capture carries no
        # context payloads by design, and must not be recorded as though it
        # refreshed the snapshot -- nor allowed to overwrite a good backtrace.
        # It is stripped before the INSERT (it is a signal, not a column).
        error_log = ErrorLog.find_or_increment_by_hash(
          error_hash,
          attributes.merge(error_hash: error_hash, _context_fidelity: storm_lite ? "lite" : "full")
        )

        # OTel: now that the error_log exists, attach its id + dedup flag + severity
        # to the parent capture span so operators can correlate to dashboard URLs.
        if span && error_log
          span.set_attribute("rails_error_dashboard.error_id", error_log.id) if error_log.id
          span.set_attribute("rails_error_dashboard.deduplicated", error_log.occurrence_count.to_i > 1)
          span.set_attribute("rails_error_dashboard.severity", error_log.severity.to_s) if error_log.respond_to?(:severity) && error_log.severity
        end

        #  Track individual error occurrence for co-occurrence analysis (if table exists)
        if defined?(ErrorOccurrence) && ErrorOccurrence.table_exists?
          begin
            occurrence_attrs = {
              error_log: error_log,
              occurred_at: attributes[:occurred_at],
              user_id: attributes[:user_id],
              request_id: error_context.request_id,
              session_id: error_context.session_id
            }
            # The release THIS event happened under. The group keeps its first
            # release; per-release counts come from here (ReleaseTimeline).
            occurrence_columns = ErrorOccurrence.column_names
            occurrence_attrs[:app_version] = attributes[:app_version] if occurrence_columns.include?("app_version")
            occurrence_attrs[:git_sha] = attributes[:git_sha] if occurrence_columns.include?("git_sha")
            occurrence_attrs = Services::EncodingSanitizer.scrub_deep(occurrence_attrs)
            ErrorOccurrence.create(ErrorOccurrence.clamp_string_attributes(occurrence_attrs))
          rescue => e
            RailsErrorDashboard::Logger.error("Failed to create error occurrence: #{e.message}")
          end
        end

        # Send notifications for new errors and reopened errors (with throttling).
        # Muted errors skip notification dispatch but still fire plugin events.
        if error_log.occurrence_count == 1
          maybe_notify(error_log) { Services::NotificationThrottler.severity_meets_minimum?(error_log) }
          PluginRegistry.dispatch(:on_error_logged, error_log)
          trigger_callbacks(error_log)
          emit_instrumentation_events(error_log)
        elsif error_log.just_reopened
          maybe_notify(error_log) { Services::NotificationThrottler.should_notify?(error_log) }
          PluginRegistry.dispatch(:on_error_reopened, error_log)
          trigger_callbacks(error_log)
          emit_instrumentation_events(error_log)
        else
          maybe_notify(error_log) { Services::NotificationThrottler.threshold_reached?(error_log) }
          PluginRegistry.dispatch(:on_error_recurred, error_log)
        end

        #  Check for baseline anomalies
        check_baseline_anomaly(error_log)

        error_log
        end
      rescue => e
        # Don't let error logging cause more errors - fail silently
        # CRITICAL: Log but never propagate exception
        RailsErrorDashboard::Logger.error("[RailsErrorDashboard] LogError command failed: #{e.class} - #{e.message}")
        RailsErrorDashboard::Logger.error("Original exception: #{@exception.class} - #{@exception.message}") if @exception
        RailsErrorDashboard::Logger.error("Context: #{@context.inspect.truncate(500)}") if @context
        RailsErrorDashboard::Logger.error(e.backtrace&.first(5)&.join("\n")) if e.backtrace

        # A worker must not report a delivery it did not make. Only the
        # store-unavailable failures are re-raised (they are worth another
        # attempt); a payload problem would fail identically on every retry,
        # so it stays swallowed here as it always has.
        raise if @worker && RETRYABLE_STORE_ERRORS.any? { |klass| e.is_a?(klass) }

        nil # Explicitly return nil, never raise
      end

      private

      # Dispatch notification if error is not muted and the throttle check passes.
      # Muted errors skip notifications but still fire plugin events/callbacks.
      # During a storm (breaker not closed) per-error notifications are
      # suppressed — a single storm notification replaces them.
      def maybe_notify(error_log)
        return if error_log.muted?
        return if Services::StormProtection::Gate.notifications_suppressed?
        return unless Services::NotificationThrottler.environment_allowed?(error_log)
        return unless yield

        Services::ErrorNotificationDispatcher.call(error_log)
        Services::NotificationThrottler.record_notification(error_log)
      rescue => e
        # The error row is already written by the time we get here. A channel
        # that cannot be reached (Redis down for the Slack job's enqueue, a
        # broken webhook config) must not take the capture down with it: the
        # caller asked us to record an error, and we did. Log, don't raise.
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Failed to dispatch notification for error #{error_log&.id}: #{e.class} - #{e.message}"
        )
      end

      # The environment this error is attributed to: an explicit context value
      # (truncated to the column) or the process-wide resolution. Never nil.
      def resolve_environment
        name = @context[:environment].to_s.strip
        return name[0, 64] unless name.empty?

        RailsErrorDashboard.configuration.current_environment
      end

      # Find or create application for multi-app support
      # Complete the fingerprint the request thread started, if it sent one.
      # The request thread hashed the identity parts into an opaque value (no
      # message text crosses the queue); this adds the application, which only
      # a worker can resolve. Same two stages as the sync path, so a capture
      # groups onto the same row whether it travelled through the queue or not.
      def canonical_hash_from_identity(application)
        opaque = @context[:_identity]
        return nil unless opaque.is_a?(String) && opaque.present?

        Services::ErrorHashGenerator.complete(opaque, application.id)
      rescue => e
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] canonical_hash_from_identity failed: #{e.class} - #{e.message}"
        )
        nil
      end

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
      rescue => e
        # AS::Notifications re-raises subscriber exceptions to the instrumenting
        # caller (fanout.rb#iterate_guarding_exceptions), so a host subscriber
        # on error_logged.rails_error_dashboard would otherwise abort a capture
        # whose row is already persisted.
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Failed to emit instrumentation events for error #{error_log&.id}: #{e.class} - #{e.message}"
        )
      end

      #  Check if error exceeds baseline and send alert if needed
      def check_baseline_anomaly(error_log)
        config = RailsErrorDashboard.configuration

        # Return early if baseline alerts are disabled or error is muted
        return unless config.enable_baseline_alerts
        return if error_log.muted?
        return unless Services::NotificationThrottler.environment_allowed?(error_log)
        return unless defined?(Queries::BaselineStats)
        return unless defined?(BaselineAlertJob)

        # Get baseline anomaly info
        anomaly = error_log.baseline_anomaly(sensitivity: config.baseline_alert_threshold_std_devs)

        # Return if no anomaly detected
        return unless anomaly[:anomaly]

        # Check if severity level should trigger alert
        return unless config.baseline_alert_severities.include?(anomaly[:level])

        # Enqueue alert job (which will handle throttling)
        BaselineAlertJob.perform_later(error_log.id, anomaly, ApplicationJob.enqueue_locale)

        RailsErrorDashboard::Logger.info(
          "Baseline alert queued for #{error_log.error_type} on #{error_log.platform}: " \
          "#{anomaly[:level]} (#{anomaly[:std_devs_above]&.round(1)}σ above baseline)"
        )
      rescue => e
        # Don't let baseline alerting cause errors
        RailsErrorDashboard::Logger.error("Failed to check baseline anomaly: #{e.message}")
      end

      # Add enriched request context fields if columns exist
      def enrich_with_request_context(attributes, error_context)
        column_names = ErrorLog.column_names

        attributes[:http_method] = error_context.http_method if column_names.include?("http_method")
        attributes[:hostname] = error_context.hostname if column_names.include?("hostname")
        attributes[:content_type] = error_context.content_type if column_names.include?("content_type")
        attributes[:request_duration_ms] = error_context.request_duration_ms if column_names.include?("request_duration_ms")
      end

      # Build cause chain JSON from pre-serialized async job context
      # Used when exception was reconstructed and has no Ruby cause
      def build_cause_json_from_context
        serialized = @context[:_serialized_cause_chain]
        return nil unless serialized.is_a?(Array) && serialized.any?

        chain = serialized.map do |entry|
          entry = entry.symbolize_keys if entry.respond_to?(:symbolize_keys)
          {
            class_name: entry[:class_name],
            message: entry[:message]&.to_s&.slice(0, 1000),
            backtrace: entry[:backtrace]&.first(20)
          }
        end

        chain.to_json
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] Failed to build cause JSON from context: #{e.message}")
        nil
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
