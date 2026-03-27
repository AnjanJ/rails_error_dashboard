# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::IssueBodyFormatter do
  def make_error(attrs = {})
    defaults = {
      error_type: "NoMethodError",
      message: "undefined method 'foo' for nil",
      backtrace: "app/models/user.rb:42:in 'save'\napp/controllers/users_controller.rb:20:in 'create'\n/gems/activerecord-7.0.4/lib/active_record/base.rb:100:in 'save!'",
      exception_cause: nil,
      environment_info: nil,
      http_method: nil,
      request_url: nil,
      hostname: nil,
      controller_name: nil,
      action_name: nil,
      platform: "Web",
      first_seen_at: Time.utc(2026, 3, 20, 14, 32, 15),
      occurrence_count: 1
    }
    double("ErrorLog", defaults.merge(attrs))
  end

  describe ".call" do
    it "includes error type as heading" do
      result = described_class.call(make_error)
      expect(result).to include("## NoMethodError")
    end

    it "includes error message" do
      result = described_class.call(make_error)
      expect(result).to include("undefined method 'foo' for nil")
    end

    it "includes app backtrace and filters framework frames" do
      result = described_class.call(make_error)
      expect(result).to include("app/models/user.rb:42")
      expect(result).not_to include("activerecord-7.0.4")
    end

    it "includes cause chain when present" do
      causes = [
        { "class_name" => "Errno::ECONNREFUSED", "message" => "Connection refused" }
      ].to_json
      result = described_class.call(make_error(exception_cause: causes))
      expect(result).to include("Errno::ECONNREFUSED")
    end

    it "includes request context when present" do
      result = described_class.call(make_error(
        request_url: "/users", http_method: "POST",
        controller_name: "users", action_name: "create"
      ))
      expect(result).to include("users#create")
      expect(result).to include("POST")
    end

    it "includes environment info when present" do
      env = { "ruby_version" => "3.2.0", "rails_version" => "7.0.4" }.to_json
      result = described_class.call(make_error(environment_info: env))
      expect(result).to include("3.2.0")
    end

    it "includes dashboard link and RED branding when provided" do
      result = described_class.call(make_error, dashboard_url: "https://app.com/error_dashboard/errors/42")
      expect(result).to include("View in Dashboard")
      expect(result).to include("https://app.com/error_dashboard/errors/42")
      expect(result).to include("RED")
      expect(result).to include("Rails Error Dashboard")
    end

    it "includes RED branding even without dashboard URL" do
      result = described_class.call(make_error)
      expect(result).to include("RED")
      expect(result).not_to include("View in Dashboard")
    end

    it "includes metadata" do
      result = described_class.call(make_error(platform: "iOS", occurrence_count: 42))
      expect(result).to include("iOS")
      expect(result).to include("42")
    end

    it "returns fallback on nil error" do
      result = described_class.call(nil)
      expect(result).to include("could not be formatted")
    end
  end
end
