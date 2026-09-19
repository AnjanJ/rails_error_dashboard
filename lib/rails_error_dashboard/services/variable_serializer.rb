# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Serialize local variables to safe JSON-compatible hash
    #
    # Handles circular references (thread-local Set of object_id),
    # depth limiting, string truncation, and per-variable rescue.
    # Never stores Binding objects.
    #
    # Sensitive data filtering uses SensitiveDataFilter.parameter_filter
    # (same approach as BreadcrumbCollector) — supports String, Symbol,
    # Regexp, and Proc patterns from Rails filter_parameters.
    #
    # Output format per variable:
    #   { type: "String", value: "hello", truncated: false }
    #
    # Safety contract:
    # - Per-variable rescue — one bad variable never crashes extraction
    # - Thread-local circular detection Set, cleaned in ensure
    # - Never raises — returns {} on total failure
    class VariableSerializer
      THREAD_KEY = :_red_variable_serializer_seen

      # Serialize a hash of variables to safe output
      # @param locals [Hash] { variable_name => raw_value }
      # @param max_count [Integer, nil] Override max variable count (defaults to local_variable_max_count)
      # @param additional_filter_patterns [Array] Extra sensitive name patterns (e.g. instance_variable_filter_patterns)
      # @return [Hash] { "variable_name" => { type:, value:, truncated:, filtered: } }
      def self.call(locals, max_count: nil, additional_filter_patterns: [])
        return {} unless locals.is_a?(Hash) && locals.any?

        config = RailsErrorDashboard.configuration
        max_count ||= config.local_variable_max_count || 15

        # Thread-local circular reference tracking
        Thread.current[THREAD_KEY] = Set.new

        result = {}
        locals.first(max_count).each do |name, value|
          name_str = name.to_s
          result[name_str] = serialize_variable(name_str, value, config)
        end

        filter_serialized(result, additional_filter_patterns: additional_filter_patterns)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] VariableSerializer.call failed: #{e.message}")
        {}
      ensure
        Thread.current[THREAD_KEY] = nil
      end

      # Serialize a single variable (per-variable rescue)
      # @return [Hash] { type:, value:, truncated: }
      def self.serialize_variable(name, value, config)
        max_depth = config.local_variable_max_depth || 3
        serialized_value = serialize_value(value, config, 0, max_depth)

        {
          type: value.class.name,
          value: serialized_value[:value],
          truncated: serialized_value[:truncated] || false
        }
      rescue => e
        { type: "Unknown", value: "(serialization error: #{e.class.name})", truncated: false }
      end
      private_class_method :serialize_variable

      # Recursively serialize a value with depth limiting and circular detection
      # @return [Hash] { value:, truncated: }
      def self.serialize_value(value, config, depth, max_depth)
        # Depth limit reached
        if depth >= max_depth
          return { value: "(depth limit reached)", truncated: true }
        end

        case value
        when NilClass
          { value: nil, truncated: false }
        when TrueClass, FalseClass
          { value: value, truncated: false }
        when Integer, Float
          { value: value, truncated: false }
        when Symbol
          { value: value.to_s, truncated: false }
        when String
          serialize_string(value, config)
        when Array
          serialize_array(value, config, depth, max_depth)
        when Hash
          serialize_hash(value, config, depth, max_depth)
        when IO, Tempfile
          { value: "#<#{value.class.name}>", truncated: false }
        when Proc
          { value: "#<Proc>", truncated: false }
        when Method, UnboundMethod
          { value: "#<#{value.class.name}: #{value.name}>", truncated: false }
        when Class, Module
          { value: value.name || value.to_s, truncated: false }
        when Regexp
          { value: value.inspect, truncated: false }
        when Range
          { value: value.to_s, truncated: false }
        else
          serialize_object(value, config, depth, max_depth)
        end
      rescue => e
        { value: "(serialization error: #{e.class.name})", truncated: false }
      end
      private_class_method :serialize_value

      def self.serialize_string(value, config)
        max_len = config.local_variable_max_string_length || 200
        if value.length > max_len
          { value: value[0, max_len], truncated: true }
        else
          { value: value, truncated: false }
        end
      end
      private_class_method :serialize_string

      def self.serialize_array(value, config, depth, max_depth)
        # Circular reference check
        seen = Thread.current[THREAD_KEY]
        if seen&.include?(value.object_id)
          return { value: "(circular reference)", truncated: false }
        end

        seen&.add(value.object_id)
        max_items = config.local_variable_max_array_items || 10
        truncated = value.length > max_items
        items = value.first(max_items).map do |item|
          serialize_value(item, config, depth + 1, max_depth)[:value]
        end

        { value: items, truncated: truncated }
      end
      private_class_method :serialize_array

      def self.serialize_hash(value, config, depth, max_depth)
        seen = Thread.current[THREAD_KEY]
        if seen&.include?(value.object_id)
          return { value: "(circular reference)", truncated: false }
        end

        seen&.add(value.object_id)
        max_items = config.local_variable_max_hash_items || 20
        truncated = value.length > max_items
        result = {}
        value.first(max_items).each do |k, v|
          key_str = k.to_s
          result[key_str] = serialize_value(v, config, depth + 1, max_depth)[:value]
        end

        { value: result, truncated: truncated }
      end
      private_class_method :serialize_hash

      def self.serialize_object(value, config, depth, max_depth)
        seen = Thread.current[THREAD_KEY]
        if seen&.include?(value.object_id)
          return { value: "(circular reference)", truncated: false }
        end

        seen&.add(value.object_id)

        # ActiveRecord objects — safe summary
        if defined?(ActiveRecord::Base) && value.is_a?(ActiveRecord::Base)
          id_str = begin
            value.id.to_s
          rescue
            nil
          end
          label = id_str ? "#<#{value.class.name} id: #{id_str}>" : "#<#{value.class.name}>"
          return { value: label, truncated: false }
        end

        # Fallback: .inspect with truncation
        max_len = config.local_variable_max_string_length || 200
        inspected = value.inspect
        if inspected.length > max_len
          { value: inspected[0, max_len], truncated: true }
        else
          { value: inspected, truncated: false }
        end
      rescue
        { value: "#<#{value.class.name rescue "Object"}>", truncated: false }
      end
      private_class_method :serialize_object

      # --- Sensitive data filtering (post-serialization) ---
      # Reuses SensitiveDataFilter.parameter_filter — same pattern as BreadcrumbCollector.
      # Applied AFTER serialization so ParameterFilter works on clean JSON-compatible values.

      # Filter all serialized variables for sensitive data
      # @param result [Hash] Serialized output from call()
      # @param additional_filter_patterns [Array] Extra sensitive name patterns
      # @return [Hash] Filtered output
      def self.filter_serialized(result, additional_filter_patterns: [])
        return result unless RailsErrorDashboard.configuration.filter_sensitive_data

        filter = effective_filter(additional_filter_patterns: additional_filter_patterns)
        return result unless filter

        result.each do |var_name, info|
          # Filter the variable name itself
          if filter_matches?(filter, var_name)
            info[:value] = "[FILTERED]"
            info[:filtered] = true
            next
          end

          # Filter string values (credit card patterns, key=value patterns)
          if info[:value].is_a?(String)
            info[:value] = SensitiveDataFilter.send(:filter_message, filter, info[:value])
          end

          # Filter nested hash keys recursively.
          #
          # The hash is wrapped back under its own variable name first, so the
          # filter sees the SAME key path Rails sees for request params. A
          # dotted pattern like "profile.private_note" is a path, not a name:
          # passing the bare inner hash dropped the "profile" segment, and the
          # value Rails redacts in params stayed readable here. Unwrapping
          # afterwards leaves the stored shape unchanged.
          if info[:value].is_a?(Hash)
            scoped = filter.filter(var_name => info[:value])[var_name]
            info[:value] = filter_hash_recursive(filter, scoped)
          end

          # Filter nested array items
          if info[:value].is_a?(Array)
            info[:value] = filter_array_recursive(filter, info[:value])
          end
        end

        result
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] VariableSerializer.filter_serialized failed: #{e.message}")
        result
      end
      private_class_method :filter_serialized

      # Build effective filter: SensitiveDataFilter base + variable-specific filter patterns
      # @param additional_filter_patterns [Array] Extra patterns (e.g. instance_variable_filter_patterns)
      # @return [ActiveSupport::ParameterFilter, nil]
      def self.effective_filter(additional_filter_patterns: [])
        base_filter = SensitiveDataFilter.parameter_filter
        return nil unless base_filter

        custom_patterns = Array(RailsErrorDashboard.configuration.local_variable_filter_patterns)
        extra_patterns = Array(additional_filter_patterns)
        return base_filter if custom_patterns.empty? && extra_patterns.empty?

        # Gather the same patterns SensitiveDataFilter uses, plus custom ones
        patterns = SensitiveDataFilter::DEFAULT_SENSITIVE_PATTERNS.dup
        if defined?(Rails) && Rails.application&.config&.respond_to?(:filter_parameters)
          patterns.concat(Array(Rails.application.config.filter_parameters))
        end
        custom_sdf = RailsErrorDashboard.configuration.sensitive_data_patterns
        patterns.concat(Array(custom_sdf)) if custom_sdf
        patterns.concat(custom_patterns)
        patterns.concat(extra_patterns)
        patterns.uniq!

        ActiveSupport::ParameterFilter.new(patterns)
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] VariableSerializer.effective_filter failed: #{e.message}")
        SensitiveDataFilter.parameter_filter
      end
      private_class_method :effective_filter

      # Check if a key name matches any filter pattern
      # Uses ParameterFilter's own matching — supports String, Symbol, Regexp, Proc
      # @return [Boolean]
      def self.filter_matches?(filter, name)
        filtered = filter.filter(name => "x")
        filtered[name] != "x"
      rescue
        false
      end
      private_class_method :filter_matches?

      # Recursively filter hash keys and values
      # @param filter [ActiveSupport::ParameterFilter]
      # @param hash [Hash]
      # @return [Hash] Filtered hash
      def self.filter_hash_recursive(filter, hash)
        # ParameterFilter handles nested key filtering natively
        filtered = filter.filter(hash)

        # Recurse into remaining complex values (arrays, nested hashes that might
        # contain further structures beyond what ParameterFilter traverses)
        filtered.each do |key, value|
          case value
          when String
            filtered[key] = SensitiveDataFilter.send(:filter_message, filter, value)
          when Array
            filtered[key] = filter_array_recursive(filter, value)
          end
        end

        filtered
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_hash_recursive failed: #{e.message}")
        hash
      end
      private_class_method :filter_hash_recursive

      # Recursively filter array items
      # @param filter [ActiveSupport::ParameterFilter]
      # @param array [Array]
      # @return [Array] Filtered array
      def self.filter_array_recursive(filter, array)
        array.map do |item|
          case item
          when String
            SensitiveDataFilter.send(:filter_message, filter, item)
          when Hash
            filter_hash_recursive(filter, item)
          when Array
            filter_array_recursive(filter, item)
          else
            item
          end
        end
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] filter_array_recursive failed: #{e.message}")
        array
      end
      private_class_method :filter_array_recursive
    end
  end
end
