# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Format error details as markdown for issue tracker body.
    #
    # Tailored for issue context — shorter than MarkdownErrorFormatter,
    # includes a link back to the dashboard, and omits system health
    # (not useful in a GitHub issue body).
    #
    # @example
    #   IssueBodyFormatter.call(error)
    #   # => "## NoMethodError\n\nundefined method 'foo'...\n\n[View in Dashboard](url)"
    class IssueBodyFormatter
      MAX_BACKTRACE_LINES = 20

      def self.call(error, dashboard_url: nil)
        new(error, dashboard_url).generate
      rescue => e
        "Error details could not be formatted: #{e.message}"
      end

      def initialize(error, dashboard_url)
        @error = error
        @dashboard_url = dashboard_url
      end

      def generate
        sections = []

        sections << heading_section
        sections << backtrace_section
        sections << cause_chain_section
        sections << request_context_section
        sections << environment_section
        sections << metadata_section
        sections << dashboard_link_section

        sections.compact.join("\n\n")
      rescue => e
        "Error details could not be formatted."
      end

      private

      def heading_section
        "## #{@error.error_type}\n\n#{@error.message}"
      end

      def backtrace_section
        raw = @error.backtrace
        return nil if raw.blank?

        lines = raw.split("\n")
        app_lines = lines.reject { |l| l.include?("/gems/") || l.include?("/ruby/") || l.include?("/vendor/") }
        app_lines = lines.first(MAX_BACKTRACE_LINES) if app_lines.empty?
        app_lines = app_lines.first(MAX_BACKTRACE_LINES)

        "### Backtrace\n\n```\n#{app_lines.join("\n")}\n```"
      end

      def cause_chain_section
        raw = @error.exception_cause
        return nil if raw.blank?

        causes = parse_json(raw)
        return nil unless causes.is_a?(Array) && causes.any?

        items = causes.each_with_index.map { |cause, i|
          "#{i + 1}. **#{cause["class_name"]}** — #{cause["message"]}"
        }

        "### Exception Cause Chain\n\n#{items.join("\n")}"
      end

      def request_context_section
        return nil if @error.request_url.blank?

        items = []
        items << "- **Controller:** #{@error.controller_name}##{@error.action_name}" if @error.controller_name.present?
        items << "- **Method:** #{@error.http_method}" if @error.http_method.present?
        items << "- **URL:** #{@error.request_url}"
        items << "- **Hostname:** #{@error.hostname}" if @error.hostname.present?

        "### Request Context\n\n#{items.join("\n")}"
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

        return nil if items.empty?

        "### Environment\n\n#{items.join("\n")}"
      end

      def metadata_section
        items = []
        items << "- **Platform:** #{@error.platform}" if @error.platform.present?
        items << "- **First seen:** #{@error.first_seen_at&.utc&.strftime("%Y-%m-%d %H:%M:%S UTC")}" if @error.first_seen_at
        items << "- **Occurrences:** #{@error.occurrence_count}" if @error.occurrence_count

        return nil if items.empty?

        "### Metadata\n\n#{items.join("\n")}"
      end

      def dashboard_link_section
        parts = []
        parts << "[View in Dashboard](#{@dashboard_url})" if @dashboard_url.present?
        parts << "Created by [RED](https://github.com/AnjanJ/rails_error_dashboard) (Rails Error Dashboard)"

        "---\n\n#{parts.join(" | ")}"
      end

      def parse_json(raw)
        return nil if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
