# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Format error details as clean Markdown for LLM debugging
    #
    # Reads data already stored in ErrorLog — zero runtime cost.
    # Called at display time only. Sections are conditional — only included
    # when data is present.
    #
    # @example
    #   RailsErrorDashboard::Services::MarkdownErrorFormatter.call(error, related_errors: related)
    #   # => "# NoMethodError\n\nundefined method 'foo' for nil\n\n## Backtrace\n\n..."
    class MarkdownErrorFormatter
      MAX_BACKTRACE_LINES = 15
      MAX_BREADCRUMBS = 10
      MAX_VARIABLES = 10

      # @param error [ErrorLog] An error log record
      # @param related_errors [Array] Related error results with :error and :similarity
      # @return [String] Markdown-formatted error details, or "" on failure
      def self.call(error, related_errors: [])
        new(error, related_errors).generate
      rescue => e
        ""
      end

      def initialize(error, related_errors)
        @error = error
        @related_errors = related_errors
      end

      # @return [String]
      def generate
        sections = []

        sections << heading_section
        sections << backtrace_section
        sections << cause_chain_section
        sections << local_variables_section
        sections << instance_variables_section
        sections << request_context_section
        sections << breadcrumbs_section
        sections << environment_section
        sections << system_health_section
        sections << related_errors_section
        sections << metadata_section

        sections.compact.join("\n\n")
      rescue => e
        ""
      end

      private

      def heading_section
        "# #{@error.error_type}\n\n#{@error.message}"
      end

      def backtrace_section
        raw = @error.backtrace
        return nil if raw.blank?

        lines = raw.split("\n")
        app_lines = lines.reject { |l| l.include?("/gems/") || l.include?("/ruby/") || l.include?("/vendor/") }
        app_lines = lines.first(MAX_BACKTRACE_LINES) if app_lines.empty?
        app_lines = app_lines.first(MAX_BACKTRACE_LINES)

        "## Backtrace\n\n```\n#{app_lines.join("\n")}\n```"
      end

      def cause_chain_section
        raw = @error.exception_cause
        return nil if raw.blank?

        causes = parse_json(raw)
        return nil unless causes.is_a?(Array) && causes.any?

        items = causes.each_with_index.map { |cause, i|
          "#{i + 1}. **#{cause["class_name"]}** — #{cause["message"]}"
        }

        "## Exception Cause Chain\n\n#{items.join("\n")}"
      end

      def local_variables_section
        raw = @error.local_variables
        return nil if raw.blank?

        vars = parse_json(raw)
        return nil unless vars.is_a?(Hash) && vars.any?

        rows = vars.first(MAX_VARIABLES).map { |name, info|
          if info.is_a?(Hash)
            "| #{name} | #{info["type"]} | #{truncate_value(info["value"])} |"
          else
            "| #{name} | — | #{truncate_value(info)} |"
          end
        }

        "## Local Variables\n\n| Variable | Type | Value |\n|----------|------|-------|\n#{rows.join("\n")}"
      end

      def instance_variables_section
        raw = @error.instance_variables
        return nil if raw.blank?

        vars = parse_json(raw)
        return nil unless vars.is_a?(Hash) && vars.any?

        self_class = vars.delete("_self_class")
        return nil if vars.empty? && self_class.nil?

        lines = []
        if self_class
          class_name = self_class.is_a?(Hash) ? self_class["value"] : self_class
          lines << "**Class:** #{class_name}"
        end

        if vars.any?
          rows = vars.first(MAX_VARIABLES).map { |name, info|
            if info.is_a?(Hash)
              "| #{name} | #{info["type"]} | #{truncate_value(info["value"])} |"
            else
              "| #{name} | — | #{truncate_value(info)} |"
            end
          }
          lines << "| Variable | Type | Value |\n|----------|------|-------|\n#{rows.join("\n")}"
        end

        "## Instance Variables\n\n#{lines.join("\n\n")}"
      end

      def request_context_section
        return nil if @error.request_url.blank?

        items = []
        items << "- **Controller:** #{@error.controller_name}##{@error.action_name}" if @error.controller_name.present?
        items << "- **Method:** #{@error.http_method}" if @error.http_method.present?
        items << "- **URL:** #{@error.request_url}"
        items << "- **Hostname:** #{@error.hostname}" if @error.hostname.present?
        items << "- **Content-Type:** #{@error.content_type}" if @error.content_type.present?
        items << "- **Duration:** #{@error.request_duration_ms}ms" if @error.request_duration_ms.present?
        items << "- **User-Agent:** #{@error.user_agent}" if @error.user_agent.present?

        params = parse_json(@error.request_params) if @error.request_params.present?
        if params.is_a?(Hash) && params.any?
          items << "\n**Request Params:**\n```json\n#{JSON.pretty_generate(params)}\n```"
        end

        "## Request Context\n\n#{items.join("\n")}"
      end

      def breadcrumbs_section
        raw = @error.breadcrumbs
        return nil if raw.blank?

        crumbs = parse_json(raw)
        return nil unless crumbs.is_a?(Array) && crumbs.any?

        # Take last N breadcrumbs (most recent, closest to error)
        crumbs = crumbs.last(MAX_BREADCRUMBS)

        rows = crumbs.map { |c|
          time = c["t"] ? Time.at(c["t"] / 1000.0).utc.strftime("%H:%M:%S.%L") : "—"
          duration = c["d"] ? "#{c["d"]}ms" : "—"
          "| #{time} | #{c["c"]} | #{truncate_value(c["m"], 80)} | #{duration} |"
        }

        "## Breadcrumbs (last #{crumbs.size})\n\n| Time | Category | Message | Duration |\n|------|----------|---------|----------|\n#{rows.join("\n")}"
      end

      def environment_section
        raw = @error.environment_info
        return nil if raw.blank?

        env = parse_json(raw)
        return nil unless env.is_a?(Hash) && env.any?

        items = []
        items << "- **Ruby:** #{env["ruby_version"]}" if env["ruby_version"]
        items << "- **Rails:** #{env["rails_version"]}" if env["rails_version"]
        items << "- **Env:** #{env["rails_env"]}" if env["rails_env"]
        items << "- **Server:** #{env["server"]}" if env["server"]
        items << "- **DB:** #{env["database_adapter"]}" if env["database_adapter"]

        version_line = []
        version_line << "- **App Version:** #{@error.app_version}" if @error.app_version.present?
        version_line << "- **Git:** #{@error.git_sha}" if @error.git_sha.present?
        items.concat(version_line)

        return nil if items.empty?

        "## Environment\n\n#{items.join("\n")}"
      end

      def system_health_section
        raw = @error.system_health
        return nil if raw.blank?

        health = parse_json(raw)
        return nil unless health.is_a?(Hash) && health.any?

        items = []

        # Process memory
        mem = health["process_memory"]
        if mem.is_a?(Hash)
          parts = []
          parts << "#{mem["rss_mb"]} MB RSS" if mem["rss_mb"]
          parts << "peak #{mem["rss_peak_mb"]} MB" if mem["rss_peak_mb"]
          parts << "swap #{mem["swap_mb"]} MB" if mem["swap_mb"] && mem["swap_mb"] > 0
          parts << "#{mem["os_threads"]} OS threads" if mem["os_threads"]
          items << "- **Memory:** #{parts.join(", ")}" if parts.any?
        elsif health["process_memory_mb"]
          items << "- **Memory:** #{health["process_memory_mb"]} MB RSS"
        end

        items << "- **Threads:** #{health["thread_count"]}" if health["thread_count"]

        # DB connection pool
        pool = health["connection_pool"]
        if pool.is_a?(Hash) && pool["size"]
          pool_parts = [ "#{pool["busy"]}/#{pool["size"]} busy" ]
          pool_parts << "#{pool["dead"]} dead" if pool["dead"].to_i > 0
          pool_parts << "#{pool["waiting"]} waiting" if pool["waiting"].to_i > 0
          items << "- **DB Pool:** #{pool_parts.join(", ")}"
        end

        # GC stats
        gc = health["gc"] || health["gc_stats"]
        if gc.is_a?(Hash)
          gc_parts = []
          gc_parts << "#{gc["major_gc_count"]} major" if gc["major_gc_count"]
          gc_parts << "#{gc["heap_live_slots"]} live slots" if gc["heap_live_slots"]
          gc_parts << "#{gc["total_allocated_objects"]} total allocated" if gc["total_allocated_objects"]
          items << "- **GC:** #{gc_parts.join(", ")}" if gc_parts.any?
        end

        # GC latest
        gc_latest = health["gc_latest"]
        if gc_latest.is_a?(Hash)
          latest_parts = []
          latest_parts << "triggered by #{gc_latest["gc_by"]}" if gc_latest["gc_by"]
          latest_parts << "state: #{gc_latest["state"]}" if gc_latest["state"]
          items << "- **Last GC:** #{latest_parts.join(", ")}" if latest_parts.any?
        end

        # Puma
        puma = health["puma"]
        if puma.is_a?(Hash) && puma["max_threads"]
          items << "- **Puma:** #{puma["running"]}/#{puma["max_threads"]} threads, backlog #{puma["backlog"]}"
        end

        # Job queue
        job = health["job_queue"]
        if job.is_a?(Hash) && job["adapter"]
          items << "- **Job Queue:** #{job["adapter"]} — #{job["failed"]} failed, #{job["queued"]} queued"
        end

        # File descriptors
        fd = health["file_descriptors"]
        if fd.is_a?(Hash) && fd["open"]
          items << "- **File Descriptors:** #{fd["open"]}/#{fd["limit"]} (#{fd["utilization_pct"]}%)"
        end

        # System load
        load = health["system_load"]
        if load.is_a?(Hash) && load["load_1m"]
          items << "- **System Load:** #{load["load_1m"]}/#{load["load_5m"]}/#{load["load_15m"]} (#{load["cpu_count"]} CPUs)"
        end

        # System memory
        sys_mem = health["system_memory"]
        if sys_mem.is_a?(Hash) && sys_mem["total_mb"]
          items << "- **System Memory:** #{sys_mem["available_mb"]}/#{sys_mem["total_mb"]} MB available (#{sys_mem["used_pct"]}% used)"
        end

        # TCP connections
        tcp = health["tcp_connections"]
        if tcp.is_a?(Hash) && tcp.values.any? { |v| v.to_i > 0 }
          tcp_parts = tcp.map { |state, count| "#{state}: #{count}" if count.to_i > 0 }.compact
          items << "- **TCP:** #{tcp_parts.join(", ")}"
        end

        # Note: RubyVM, YJIT, and ActionCable stats are omitted — they are process-wide
        # counters, not error-specific context. They add noise for LLM debugging.

        return nil if items.empty?

        "## System Health at Error Time\n\n#{items.join("\n")}"
      end

      def related_errors_section
        return nil if @related_errors.nil? || @related_errors.empty?

        items = @related_errors.map { |r|
          # related_errors can be plain ErrorLog objects or wrapped objects with .error/.similarity
          error = r.respond_to?(:error) ? r.error : r
          if r.respond_to?(:similarity)
            pct = (r.similarity * 100).round(1)
            "- `#{error.error_type}` — #{error.message} (#{pct}% similar, #{error.occurrence_count} occurrences)"
          else
            "- `#{error.error_type}` — #{error.message} (#{error.occurrence_count} occurrences)"
          end
        }

        "## Related Errors\n\n#{items.join("\n")}"
      end

      def metadata_section
        items = []
        items << "- **Platform:** #{@error.platform}" if @error.platform.present?
        items << "- **First seen:** #{@error.first_seen_at&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC")}" if @error.first_seen_at
        items << "- **Occurrences:** #{@error.occurrence_count}" if @error.occurrence_count
        items << "- **User ID:** #{@error.user_id}" if @error.user_id.present?

        return nil if items.empty?

        "## Metadata\n\n#{items.join("\n")}"
      end

      def parse_json(raw)
        return nil if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def truncate_value(value, max_length = 200)
        str = value.to_s
        str.length > max_length ? "#{str[0...max_length]}..." : str
      end
    end
  end
end
