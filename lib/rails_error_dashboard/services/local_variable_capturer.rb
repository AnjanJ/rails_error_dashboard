# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # TracePoint lifecycle manager for capturing local variables and instance
    # variables at raise time.
    #
    # Uses TracePoint(:raise) which only fires when exceptions are raised (rare
    # in normal request flow). Sentry ships this in production (proven safe).
    #
    # Safety contract:
    # - Default OFF (opt-in via config.enable_local_variables / enable_instance_variables)
    # - Never stores Binding objects — extracts vars immediately in callback
    # - Strings, arrays and hashes are snapshotted (shallow copy, bounded by the
    #   serializer's limits) at raise time; other objects are kept by reference,
    #   so their state is whatever it is when the error is serialized
    # - Every callback wrapped in rescue => e (never raises)
    # - Per-variable rescue in extraction
    # - Skips SystemExit, SignalException, Interrupt
    # - Skips non-app-code paths (gems, vendor, stdlib, this gem)
    # - Re-raise guard: skips if exception already has @_red_locals / @_red_instance_vars
    class LocalVariableCapturer
      # Instance variable names used to attach captured data to the exception
      LOCALS_IVAR = :@_red_locals
      INSTANCE_VARS_IVAR = :@_red_instance_vars

      class << self
        # Enable the TracePoint(:raise) hook globally
        def enable!
          return if enabled?

          @tracepoint = TracePoint.new(:raise) do |tp|
            on_raise(tp)
          rescue => e
            # CRITICAL: never let the callback crash the app
            RailsErrorDashboard::Logger.debug(
              "[RailsErrorDashboard] LocalVariableCapturer callback error: #{e.class} - #{e.message}"
            )
          end

          @tracepoint.enable
        end

        # Disable the TracePoint hook
        def disable!
          @tracepoint&.disable
          @tracepoint = nil
        end

        # Check if currently enabled
        def enabled?
          @tracepoint&.enabled? == true
        end

        # Extract captured locals from an exception (if any)
        # @param exception [Exception] The exception to check
        # @return [Hash, nil] Raw locals hash or nil
        def extract(exception)
          return nil unless exception.is_a?(Exception)
          return nil unless exception.instance_variable_defined?(LOCALS_IVAR)

          exception.instance_variable_get(LOCALS_IVAR)
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] LocalVariableCapturer.extract failed: #{e.message}"
          )
          nil
        end

        # Extract captured instance variables from an exception (if any)
        # @param exception [Exception] The exception to check
        # @return [Hash, nil] Raw instance vars hash or nil
        def extract_instance_vars(exception)
          return nil unless exception.is_a?(Exception)
          return nil unless exception.instance_variable_defined?(INSTANCE_VARS_IVAR)

          exception.instance_variable_get(INSTANCE_VARS_IVAR)
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] LocalVariableCapturer.extract_instance_vars failed: #{e.message}"
          )
          nil
        end

        private

        # TracePoint callback — runs on every :raise event
        # Filter chain ordered cheapest-first for minimal overhead
        def on_raise(tp)
          exception = tp.raised_exception
          config = RailsErrorDashboard.configuration

          # 1. Re-raise guard: skip if already captured both
          locals_captured = exception.instance_variable_defined?(LOCALS_IVAR)
          ivars_captured = exception.instance_variable_defined?(INSTANCE_VARS_IVAR)
          return if locals_captured && ivars_captured

          # 2. Skip system/signal exceptions
          return if exception.is_a?(SystemExit) || exception.is_a?(SignalException) || exception.is_a?(Interrupt)

          # 3. Skip common flow-control exceptions (avoid expensive tp.binding call)
          return if defined?(ActionController::RoutingError) && exception.is_a?(ActionController::RoutingError)
          return if defined?(ActiveRecord::RecordNotFound) && exception.is_a?(ActiveRecord::RecordNotFound)
          return if defined?(ActionController::UnknownFormat) && exception.is_a?(ActionController::UnknownFormat)

          # 4. Skip non-app-code paths
          path = tp.path.to_s
          return if skip_path?(path)

          # 5. Extract local variables from the binding (if enabled and not already captured)
          if config.enable_local_variables && !locals_captured
            locals = extract_locals(tp.binding)
            exception.instance_variable_set(LOCALS_IVAR, locals) if locals && locals.any?
          end

          # 6. Extract instance variables from tp.self (if enabled and not already captured)
          if config.enable_instance_variables && !ivars_captured
            ivars = capture_instance_vars(tp.self)
            exception.instance_variable_set(INSTANCE_VARS_IVAR, ivars) if ivars && ivars.any?
          end
        end

        # A value as it is NOW, for the kinds of value that are cheap to copy.
        #
        # The exception is serialized later, after the stack has unwound —
        # and ensure blocks and rescue handlers run in between, mutating the
        # very state worth seeing (`state["phase"] = "cleanup"`, `@conn = nil`).
        # A reference would show the post-cleanup value and call it the value
        # "at raise". Strings, arrays and hashes get a one-level copy, bounded
        # by what the serializer will keep anyway (+1 so it still knows the
        # original was longer). Anything else is left as a reference: copying
        # arbitrary application objects is neither safe nor cheap. Nested
        # containers inside the copy are therefore still references.
        def snapshot_value(value)
          config = RailsErrorDashboard.configuration
          case value
          when String
            value.frozen? ? value : value[0, (config.local_variable_max_string_length || 200) + 1]
          when Array
            value.first((config.local_variable_max_array_items || 10) + 1)
          when Hash
            value.first((config.local_variable_max_hash_items || 20) + 1).to_h
          else
            value
          end
        rescue
          value
        end

        # Check if the path should be skipped (gem code, vendor, stdlib, this gem)
        def skip_path?(path)
          path.include?("/gems/") ||
            path.include?("/vendor/") ||
            path.include?("/ruby/") ||
            path.include?("rails_error_dashboard") ||
            path.start_with?("<") ||   # Ruby 3.3+: <eval>, <irb>, etc.
            path.start_with?("(")      # Ruby 3.2: (eval), (irb), etc.
        end

        # Extract local variables from a binding (per-variable rescue)
        # @param binding_obj [Binding] The binding at raise time
        # @return [Hash] { variable_name_symbol => raw_value }
        def extract_locals(binding_obj)
          return nil unless binding_obj

          var_names = binding_obj.local_variables
          return nil if var_names.empty?

          # Respect max count limit at extraction time (reduces memory on exception object)
          max_count = RailsErrorDashboard.configuration.local_variable_max_count || 15
          var_names = var_names.first(max_count)

          locals = {}
          var_names.each do |name|
            locals[name] = snapshot_value(binding_obj.local_variable_get(name))
          rescue => e
            locals[name] = "(extraction error: #{e.class.name})"
          end

          locals
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] extract_locals failed: #{e.message}"
          )
          nil
        end

        # Extract instance variables from the receiver object (tp.self)
        # Never stores the object reference — extracts values immediately.
        # @param obj [Object] The receiver where the exception was raised
        # @return [Hash, nil] { :_self_class => class_name, :@ivar_name => raw_value }
        def capture_instance_vars(obj)
          return nil if obj.nil?

          config = RailsErrorDashboard.configuration
          max_count = config.instance_variable_max_count || 20

          # Get instance variable names (safe — instance_variables is always available)
          ivar_names = obj.instance_variables
          return nil if ivar_names.empty?

          # Filter out internal ivars:
          # - @_red_* — our own gem ivars (e.g. @_red_locals, @_red_instance_vars)
          # - @_* — Rails framework internals (e.g. @_request, @_response, @_action_name)
          ivar_names = ivar_names.reject { |name| name.to_s.start_with?("@_") }
          return nil if ivar_names.empty?

          # Respect max count limit
          ivar_names = ivar_names.first(max_count)

          result = {}

          # Add metadata: class name of the receiver
          result[:_self_class] = begin
            obj.class.name || obj.class.to_s
          rescue
            "Unknown"
          end

          # Extract each instance variable (per-variable rescue)
          ivar_names.each do |name|
            result[name] = snapshot_value(obj.instance_variable_get(name))
          rescue => e
            result[name] = "(extraction error: #{e.class.name})"
          end

          result
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] capture_instance_vars failed: #{e.message}"
          )
          nil
        end
      end
    end
  end
end
