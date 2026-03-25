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
        lines << "**Class:** #{self_class}" if self_class

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
        items << "- **Method:** #{@error.http_method}" if @error.http_method.present?
        items << "- **URL:** #{@error.request_url}"
        items << "- **Hostname:** #{@error.hostname}" if @error.hostname.present?
        items << "- **Content-Type:** #{@error.content_type}" if @error.content_type.present?
        items << "- **Duration:** #{@error.request_duration_ms}ms" if @error.request_duration_ms.present?
        items << "- **IP:** #{@error.ip_address}" if @error.ip_address.present?

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
        items << "- **Memory:** #{health["process_memory_mb"]} MB RSS" if health["process_memory_mb"]
        items << "- **Threads:** #{health["thread_count"]}" if health["thread_count"]

        pool = health["connection_pool"]
        if pool.is_a?(Hash)
          items << "- **DB Pool:** #{pool["busy"]}/#{pool["size"]} busy" if pool["size"]
        end

        gc = health["gc_stats"]
        if gc.is_a?(Hash)
          items << "- **GC:** #{gc["major_gc_count"]} major cycles" if gc["major_gc_count"]
        end

        return nil if items.empty?

        "## System Health at Error Time\n\n#{items.join("\n")}"
      end

      def related_errors_section
        return nil if @related_errors.nil? || @related_errors.empty?

        items = @related_errors.map { |r|
          pct = (r.similarity * 100).round(1)
          "- `#{r.error.error_type}` — #{r.error.message} (#{pct}% similar, #{r.error.occurrence_count} occurrences)"
        }

        "## Related Errors\n\n#{items.join("\n")}"
      end

      def metadata_section
        items = []
        items << "- **Severity:** #{@error.severity}" if @error.severity.present?
        items << "- **Status:** #{@error.status}" if @error.status.present?
        items << "- **Priority:** P#{3 - @error.priority_level}" if @error.priority_level.present?
        items << "- **Platform:** #{@error.platform}" if @error.platform.present?
        items << "- **First seen:** #{@error.first_seen_at&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC")}" if @error.first_seen_at
        items << "- **Occurrences:** #{@error.occurrence_count}" if @error.occurrence_count
        items << "- **Assigned to:** #{@error.assigned_to}" if @error.assigned_to.present?

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
