# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::NotificationHelpers do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "NoMethodError",
      message: "undefined method 'foo'",
      controller_name: "users",
      action_name: "show",
      request_url: "http://example.com/users/1",
      platform: "Web",
      ip_address: "192.168.1.1")
  end

  describe ".dashboard_url" do
    before { RailsErrorDashboard.reset_configuration! }

    it "returns URL with default base" do
      expect(described_class.dashboard_url(error_log)).to eq(
        "http://localhost:3000/error_dashboard/errors/#{error_log.id}"
      )
    end

    it "uses configured base URL" do
      RailsErrorDashboard.configure { |c| c.dashboard_base_url = "https://app.example.com" }
      expect(described_class.dashboard_url(error_log)).to eq(
        "https://app.example.com/error_dashboard/errors/#{error_log.id}"
      )
    end
  end

  describe ".truncate_message" do
    it "returns short messages as-is" do
      expect(described_class.truncate_message("short")).to eq("short")
    end

    it "truncates long messages with ellipsis" do
      long = "a" * 600
      result = described_class.truncate_message(long)
      expect(result.length).to eq(503)
      expect(result).to end_with("...")
    end

    it "accepts custom length" do
      expect(described_class.truncate_message("hello world", 5)).to eq("hello...")
    end

    it "returns empty string for nil" do
      expect(described_class.truncate_message(nil)).to eq("")
    end
  end

  describe ".extract_backtrace" do
    it "extracts lines from string backtrace" do
      bt = "line1\nline2\nline3"
      expect(described_class.extract_backtrace(bt)).to eq(%w[line1 line2 line3])
    end

    it "limits to specified count" do
      bt = (1..30).map { |i| "line#{i}" }.join("\n")
      expect(described_class.extract_backtrace(bt, 5).length).to eq(5)
    end

    it "returns empty array for nil" do
      expect(described_class.extract_backtrace(nil)).to eq([])
    end
  end

  describe ".extract_first_backtrace_line" do
    it "returns first line" do
      expect(described_class.extract_first_backtrace_line("app/models/user.rb:5\nother")).to eq("app/models/user.rb:5")
    end

    it "truncates long first line" do
      long_line = "a" * 150
      result = described_class.extract_first_backtrace_line(long_line)
      expect(result.length).to eq(103)
      expect(result).to end_with("...")
    end

    it "returns N/A for nil" do
      expect(described_class.extract_first_backtrace_line(nil)).to eq("N/A")
    end
  end

  describe ".platform_emoji" do
    it "returns correct emoji for each platform" do
      expect(described_class.platform_emoji("iOS")).to eq("📱")
      expect(described_class.platform_emoji("android")).to eq("🤖")
      expect(described_class.platform_emoji("API")).to eq("🔌")
      expect(described_class.platform_emoji("Web")).to eq("💻")
      expect(described_class.platform_emoji(nil)).to eq("💻")
    end
  end

  describe ".format_time" do
    it "formats time" do
      time = Time.utc(2026, 2, 10, 14, 30, 0)
      expect(described_class.format_time(time)).to eq("2026-02-10 14:30:00 UTC")
    end

    it "returns N/A for nil" do
      expect(described_class.format_time(nil)).to eq("N/A")
    end
  end

  describe ".parse_request_params" do
    it "parses valid JSON" do
      expect(described_class.parse_request_params('{"key":"value"}')).to eq("key" => "value")
    end

    it "returns empty hash for nil" do
      expect(described_class.parse_request_params(nil)).to eq({})
    end

    it "returns empty hash for invalid JSON" do
      expect(described_class.parse_request_params("not json")).to eq({})
    end
  end

  describe ".error_source" do
    it "returns controller#action when both present" do
      expect(described_class.error_source(error_log)).to eq("users#show")
    end

    it "returns request_url as fallback" do
      error_log.controller_name = nil
      expect(described_class.error_source(error_log)).to eq("http://example.com/users/1")
    end

    it "returns platform as last fallback" do
      error_log.controller_name = nil
      error_log.request_url = nil
      expect(described_class.error_source(error_log)).to eq("Web")
    end
  end
end
