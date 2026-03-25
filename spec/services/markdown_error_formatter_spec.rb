# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::MarkdownErrorFormatter do
  def make_error(attrs = {})
    defaults = {
      error_type: "NoMethodError",
      message: "undefined method 'foo' for nil",
      backtrace: "app/models/user.rb:42:in 'save'\napp/controllers/users_controller.rb:20:in 'create'\n/gems/activerecord-7.0.4/lib/active_record/base.rb:100:in 'save!'",
      exception_cause: nil,
      local_variables: nil,
      instance_variables: nil,
      breadcrumbs: nil,
      system_health: nil,
      environment_info: nil,
      http_method: nil,
      request_url: nil,
      hostname: nil,
      content_type: nil,
      request_duration_ms: nil,
      ip_address: nil,
      user_agent: nil,
      request_params: nil,
      severity: "high",
      priority_level: nil,
      status: "new",
      assigned_to: nil,
      first_seen_at: Time.utc(2026, 3, 20, 14, 32, 15),
      occurred_at: Time.utc(2026, 3, 25, 10, 0, 0),
      occurrence_count: 1,
      user_id: nil,
      platform: "Web",
      app_version: nil,
      git_sha: nil
    }
    double("ErrorLog", defaults.merge(attrs))
  end

  describe ".call" do
    context "happy path" do
      it "includes error type as heading" do
        result = described_class.call(make_error)
        expect(result).to include("# NoMethodError")
      end

      it "includes error message" do
        result = described_class.call(make_error)
        expect(result).to include("undefined method 'foo' for nil")
      end

      it "includes app backtrace and filters framework frames" do
        result = described_class.call(make_error)
        expect(result).to include("app/models/user.rb:42")
        expect(result).to include("app/controllers/users_controller.rb:20")
        expect(result).not_to include("activerecord-7.0.4")
      end

      it "includes backtrace section header" do
        result = described_class.call(make_error)
        expect(result).to include("## Backtrace")
      end
    end

    context "conditional sections" do
      it "omits cause chain section when exception_cause is nil" do
        result = described_class.call(make_error(exception_cause: nil))
        expect(result).not_to include("## Exception Cause Chain")
      end

      it "omits local variables section when local_variables is nil" do
        result = described_class.call(make_error(local_variables: nil))
        expect(result).not_to include("## Local Variables")
      end

      it "omits instance variables section when instance_variables is nil" do
        result = described_class.call(make_error(instance_variables: nil))
        expect(result).not_to include("## Instance Variables")
      end

      it "omits breadcrumbs section when breadcrumbs is nil" do
        result = described_class.call(make_error(breadcrumbs: nil))
        expect(result).not_to include("## Breadcrumbs")
      end

      it "omits system health section when system_health is nil" do
        result = described_class.call(make_error(system_health: nil))
        expect(result).not_to include("## System Health")
      end

      it "omits request context section when request_url is nil" do
        result = described_class.call(make_error(request_url: nil))
        expect(result).not_to include("## Request Context")
      end

      it "omits environment section when environment_info is nil" do
        result = described_class.call(make_error(environment_info: nil))
        expect(result).not_to include("## Environment")
      end

      it "omits related errors section when no related errors passed" do
        result = described_class.call(make_error, related_errors: [])
        expect(result).not_to include("## Related Errors")
      end
    end

    context "exception cause chain" do
      it "formats cause chain as numbered list" do
        causes = [
          { "class_name" => "Errno::ECONNREFUSED", "message" => "Connection refused" },
          { "class_name" => "Net::OpenTimeout", "message" => "execution expired" }
        ].to_json

        result = described_class.call(make_error(exception_cause: causes))
        expect(result).to include("## Exception Cause Chain")
        expect(result).to include("**Errno::ECONNREFUSED**")
        expect(result).to include("Connection refused")
        expect(result).to include("**Net::OpenTimeout**")
        expect(result).to include("execution expired")
      end
    end

    context "local variables" do
      it "formats local variables as a markdown table" do
        locals = {
          "user" => { "type" => "User", "value" => "#<User id: 42>" },
          "email" => { "type" => "String", "value" => "user@example.com" }
        }.to_json

        result = described_class.call(make_error(local_variables: locals))
        expect(result).to include("## Local Variables")
        expect(result).to include("| user | User |")
        expect(result).to include("| email | String |")
        expect(result).to include("#<User id: 42>")
      end

      it "preserves [FILTERED] for sensitive data" do
        locals = {
          "password" => { "type" => "String", "value" => "[FILTERED]", "filtered" => true }
        }.to_json

        result = described_class.call(make_error(local_variables: locals))
        expect(result).to include("[FILTERED]")
      end

      it "truncates to max 10 variables" do
        locals = (1..15).each_with_object({}) { |i, h|
          h["var_#{i}"] = { "type" => "String", "value" => "val_#{i}" }
        }.to_json

        result = described_class.call(make_error(local_variables: locals))
        expect(result).to include("var_10")
        expect(result).not_to include("var_11")
      end
    end

    context "instance variables" do
      it "formats instance variables as a markdown table" do
        ivars = {
          "_self_class" => "UsersController",
          "@action_name" => { "type" => "String", "value" => "show" }
        }.to_json

        result = described_class.call(make_error(instance_variables: ivars))
        expect(result).to include("## Instance Variables")
        expect(result).to include("@action_name")
        expect(result).to include("show")
      end

      it "includes _self_class as context when it is a plain string" do
        ivars = { "_self_class" => "UsersController" }.to_json
        result = described_class.call(make_error(instance_variables: ivars))
        expect(result).to include("**Class:** UsersController")
      end

      it "extracts _self_class value when it is a serialized hash" do
        ivars = {
          "_self_class" => { "type" => "String", "value" => "QuestService", "truncated" => false },
          "@name" => { "type" => "String", "value" => "test" }
        }.to_json
        result = described_class.call(make_error(instance_variables: ivars))
        expect(result).to include("**Class:** QuestService")
        expect(result).not_to include("truncated")
      end
    end

    context "request context" do
      it "includes HTTP method and URL" do
        result = described_class.call(make_error(
          http_method: "POST",
          request_url: "/users",
          hostname: "api.example.com"
        ))
        expect(result).to include("## Request Context")
        expect(result).to include("POST")
        expect(result).to include("/users")
        expect(result).to include("api.example.com")
      end

      it "includes duration when present" do
        result = described_class.call(make_error(
          request_url: "/users",
          request_duration_ms: 245
        ))
        expect(result).to include("245ms")
      end

      it "includes user agent when present" do
        result = described_class.call(make_error(
          request_url: "/users",
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X)"
        ))
        expect(result).to include("Mozilla/5.0")
      end

      it "includes request params as formatted JSON" do
        result = described_class.call(make_error(
          request_url: "/users",
          request_params: '{"name":"Gandalf","role":"wizard"}'
        ))
        expect(result).to include("**Request Params:**")
        expect(result).to include('"name": "Gandalf"')
        expect(result).to include('"role": "wizard"')
      end

      it "omits request params when nil" do
        result = described_class.call(make_error(
          request_url: "/users",
          request_params: nil
        ))
        expect(result).not_to include("Request Params")
      end

      it "handles malformed request params JSON gracefully" do
        result = described_class.call(make_error(
          request_url: "/users",
          request_params: "not json{"
        ))
        expect(result).not_to include("Request Params")
      end
    end

    context "breadcrumbs" do
      it "formats breadcrumbs as a table" do
        crumbs = [
          { "t" => 1706025735123, "c" => "controller", "m" => "UsersController#show", "d" => 45 },
          { "t" => 1706025735168, "c" => "sql", "m" => "SELECT * FROM users", "d" => 23 }
        ].to_json

        result = described_class.call(make_error(breadcrumbs: crumbs))
        expect(result).to include("## Breadcrumbs")
        expect(result).to include("controller")
        expect(result).to include("UsersController#show")
        expect(result).to include("sql")
      end

      it "truncates to last 10 breadcrumbs" do
        crumbs = (1..15).map { |i|
          { "t" => 1706025735000 + i, "c" => "sql", "m" => "query_#{i}" }
        }.to_json

        result = described_class.call(make_error(breadcrumbs: crumbs))
        expect(result).to include("query_15")
        expect(result).to include("query_6")
        expect(result).not_to include("query_5")
      end
    end

    context "environment info" do
      it "includes ruby and rails versions" do
        env = {
          "ruby_version" => "3.2.0",
          "rails_version" => "7.0.4",
          "rails_env" => "production",
          "server" => "puma",
          "database_adapter" => "postgresql"
        }.to_json

        result = described_class.call(make_error(environment_info: env))
        expect(result).to include("## Environment")
        expect(result).to include("3.2.0")
        expect(result).to include("7.0.4")
        expect(result).to include("production")
      end
    end

    context "system health" do
      it "includes memory and thread info" do
        health = {
          "process_memory_mb" => 245,
          "thread_count" => 12,
          "gc_stats" => { "major_gc_count" => 42 },
          "connection_pool" => { "size" => 10, "busy" => 3 }
        }.to_json

        result = described_class.call(make_error(system_health: health))
        expect(result).to include("## System Health")
        expect(result).to include("245")
        expect(result).to include("12")
      end
    end

    context "related errors" do
      it "lists wrapped related errors with similarity percentage" do
        related = [
          double("Related1",
            error: double("E1", error_type: "TypeError", message: "no implicit conversion", occurrence_count: 15),
            similarity: 0.857),
          double("Related2",
            error: double("E2", error_type: "NameError", message: "undefined local variable", occurrence_count: 8),
            similarity: 0.721)
        ]

        result = described_class.call(make_error, related_errors: related)
        expect(result).to include("## Related Errors")
        expect(result).to include("TypeError")
        expect(result).to include("no implicit conversion")
        expect(result).to include("85.7%")
        expect(result).to include("NameError")
      end

      it "lists plain ErrorLog related errors without similarity" do
        related = [
          double("E1", error_type: "TypeError", message: "no implicit conversion", occurrence_count: 15),
          double("E2", error_type: "NameError", message: "undefined local variable", occurrence_count: 8)
        ]

        result = described_class.call(make_error, related_errors: related)
        expect(result).to include("## Related Errors")
        expect(result).to include("TypeError")
        expect(result).to include("15 occurrences")
        expect(result).not_to include("similar")
      end
    end

    context "metadata section" do
      it "includes severity and status" do
        result = described_class.call(make_error(severity: "critical", status: "investigating"))
        expect(result).to include("## Metadata")
        expect(result).to include("critical")
        expect(result).to include("investigating")
      end

      it "includes occurrence count" do
        result = described_class.call(make_error(occurrence_count: 127))
        expect(result).to include("127")
      end

      it "includes assigned_to when present" do
        result = described_class.call(make_error(assigned_to: "alice"))
        expect(result).to include("alice")
      end

      it "omits assigned_to when nil" do
        result = described_class.call(make_error(assigned_to: nil))
        expect(result).not_to include("Assigned")
      end
    end

    context "error resilience" do
      it "returns empty string on nil input" do
        expect(described_class.call(nil)).to eq("")
      end

      it "returns empty string when error raises" do
        error = double("BrokenError")
        allow(error).to receive(:error_type).and_raise(RuntimeError, "boom")
        expect(described_class.call(error)).to eq("")
      end

      it "handles malformed JSON in local_variables gracefully" do
        result = described_class.call(make_error(local_variables: "not json{"))
        expect(result).not_to include("## Local Variables")
      end

      it "handles malformed JSON in breadcrumbs gracefully" do
        result = described_class.call(make_error(breadcrumbs: "broken"))
        expect(result).not_to include("## Breadcrumbs")
      end
    end
  end
end
