# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SlackPayloadBuilder do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "NoMethodError",
      message: "undefined method 'foo' for nil",
      controller_name: "users",
      action_name: "show",
      platform: "Web",
      request_url: "http://example.com/users/1",
      ip_address: "192.168.1.1")
  end

  describe ".call" do
    subject(:payload) { described_class.call(error_log) }

    it "returns a hash with text and blocks" do
      expect(payload).to be_a(Hash)
      expect(payload[:text]).to eq("🚨 New Error Alert")
      expect(payload[:blocks]).to be_an(Array)
    end

    it "includes header block" do
      header = payload[:blocks].find { |b| b[:type] == "header" }
      expect(header[:text][:text]).to eq("🚨 Error Alert")
    end

    it "includes error type in fields" do
      section = payload[:blocks].find { |b| b[:type] == "section" && b[:fields] }
      error_field = section[:fields].find { |f| f[:text].include?("Error Type") }
      expect(error_field[:text]).to include("NoMethodError")
    end

    it "includes message block" do
      message_block = payload[:blocks].find { |b| b[:type] == "section" && b.dig(:text, :text)&.include?("Message") }
      expect(message_block[:text][:text]).to include("undefined method")
    end

    it "includes actions block with dashboard link" do
      actions = payload[:blocks].find { |b| b[:type] == "actions" }
      expect(actions[:elements].first[:url]).to include("/error_dashboard/errors/#{error_log.id}")
    end

    it "includes context block with error ID" do
      context = payload[:blocks].find { |b| b[:type] == "context" }
      expect(context[:elements].first[:text]).to include(error_log.id.to_s)
    end

    it "excludes user block when no user_id" do
      block_count = payload[:blocks].compact.length
      # Should not include user section (nil gets compacted out)
      user_blocks = payload[:blocks].compact.select { |b| b[:type] == "section" && b[:fields]&.any? { |f| f[:text].include?("User") } }
      expect(user_blocks).to be_empty
    end

    it "includes request block when request_url present" do
      request_block = payload[:blocks].find { |b| b[:type] == "section" && b.dig(:text, :text)&.include?("Request URL") }
      expect(request_block[:text][:text]).to include("example.com")
    end
  end
end
