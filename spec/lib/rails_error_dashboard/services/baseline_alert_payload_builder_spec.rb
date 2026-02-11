# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::BaselineAlertPayloadBuilder do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "TimeoutError",
      message: "Request timed out after 30 seconds",
      platform: "API")
  end

  let(:anomaly_data) do
    {
      level: :high,
      std_devs_above: 3.5,
      threshold: 15.0,
      baseline_type: "daily"
    }
  end

  describe ".slack_payload" do
    subject(:payload) { described_class.slack_payload(error_log, anomaly_data) }

    it "returns a hash with text and blocks" do
      expect(payload[:text]).to eq("🚨 Baseline Anomaly Alert")
      expect(payload[:blocks]).to be_an(Array)
    end

    it "includes error type in fields" do
      fields_block = payload[:blocks].find { |b| b[:type] == "section" && b[:fields] }
      error_field = fields_block[:fields].find { |f| f[:text].include?("Error Type") }
      expect(error_field[:text]).to include("TimeoutError")
    end

    it "includes severity with emoji" do
      fields_block = payload[:blocks].find { |b| b[:type] == "section" && b[:fields] }
      severity_field = fields_block[:fields].find { |f| f[:text].include?("Severity") }
      expect(severity_field[:text]).to include("🟠")
      expect(severity_field[:text]).to include("HIGH")
    end

    it "includes standard deviations" do
      fields_block = payload[:blocks].find { |b| b[:type] == "section" && b[:fields] }
      std_field = fields_block[:fields].find { |f| f[:text].include?("Standard Deviations") }
      expect(std_field[:text]).to include("3.5σ")
    end

    it "includes baseline info" do
      info_block = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Baseline Info") }
      expect(info_block[:text][:text]).to include("15.0 errors")
      expect(info_block[:text][:text]).to include("daily")
    end

    it "includes dashboard link button" do
      actions = payload[:blocks].find { |b| b[:type] == "actions" }
      expect(actions[:elements].first[:url]).to include("/error_dashboard/errors/#{error_log.id}")
    end
  end

  describe ".discord_payload" do
    subject(:payload) { described_class.discord_payload(error_log, anomaly_data) }

    it "returns a hash with embeds" do
      expect(payload[:embeds]).to be_an(Array)
      expect(payload[:embeds].length).to eq(1)
    end

    it "includes severity color for high" do
      expect(payload[:embeds].first[:color]).to eq(16744192)
    end

    it "includes all fields" do
      fields = payload[:embeds].first[:fields]
      expect(fields.find { |f| f[:name] == "Error Type" }[:value]).to eq("TimeoutError")
      expect(fields.find { |f| f[:name] == "Platform" }[:value]).to eq("API")
      expect(fields.find { |f| f[:name] == "Severity" }[:value]).to eq("HIGH")
    end
  end

  describe ".webhook_payload" do
    subject(:payload) { described_class.webhook_payload(error_log, anomaly_data) }

    it "sets event to baseline_anomaly" do
      expect(payload[:event]).to eq("baseline_anomaly")
    end

    it "includes error details" do
      expect(payload[:error][:type]).to eq("TimeoutError")
      expect(payload[:error][:platform]).to eq("API")
    end

    it "includes anomaly details" do
      expect(payload[:anomaly][:level]).to eq("high")
      expect(payload[:anomaly][:std_devs_above]).to eq(3.5)
      expect(payload[:anomaly][:threshold]).to eq(15.0)
      expect(payload[:anomaly][:baseline_type]).to eq("daily")
    end

    it "includes dashboard URL" do
      expect(payload[:dashboard_url]).to include("/error_dashboard/errors/#{error_log.id}")
    end
  end

  describe ".anomaly_emoji" do
    it "returns correct emojis" do
      expect(described_class.anomaly_emoji(:critical)).to eq("🔴")
      expect(described_class.anomaly_emoji(:high)).to eq("🟠")
      expect(described_class.anomaly_emoji(:elevated)).to eq("🟡")
      expect(described_class.anomaly_emoji(:unknown)).to eq("⚪")
    end
  end

  describe ".anomaly_color" do
    it "returns correct Discord colors" do
      expect(described_class.anomaly_color(:critical)).to eq(15158332)
      expect(described_class.anomaly_color(:high)).to eq(16744192)
      expect(described_class.anomaly_color(:elevated)).to eq(16776960)
      expect(described_class.anomaly_color(:unknown)).to eq(9807270)
    end
  end
end
