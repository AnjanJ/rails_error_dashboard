# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::PagerdutyPayloadBuilder do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "SecurityError",
      message: "Unauthorized access detected",
      controller_name: "admin",
      action_name: "destroy",
      platform: "Web",
      occurrence_count: 1,
      backtrace: "app/controllers/admin_controller.rb:15\napp/middleware/auth.rb:8")
  end

  describe ".call" do
    subject(:payload) { described_class.call(error_log, routing_key: "test-key-123") }

    it "includes routing key" do
      expect(payload[:routing_key]).to eq("test-key-123")
    end

    it "sets event_action to trigger" do
      expect(payload[:event_action]).to eq("trigger")
    end

    it "includes summary with error type and platform" do
      expect(payload[:payload][:summary]).to include("SecurityError")
      expect(payload[:payload][:summary]).to include("Web")
    end

    it "sets severity to critical" do
      expect(payload[:payload][:severity]).to eq("critical")
    end

    it "includes error source as controller#action" do
      expect(payload[:payload][:source]).to eq("admin#destroy")
    end

    it "includes custom details" do
      details = payload[:payload][:custom_details]
      expect(details[:message]).to eq("Unauthorized access detected")
      expect(details[:controller]).to eq("admin")
      expect(details[:action]).to eq("destroy")
      expect(details[:platform]).to eq("Web")
      expect(details[:occurrences]).to eq(1)
      expect(details[:error_id]).to eq(error_log.id)
    end

    it "includes backtrace in custom details" do
      expect(payload[:payload][:custom_details][:backtrace]).to be_an(Array)
      expect(payload[:payload][:custom_details][:backtrace].first).to include("admin_controller.rb")
    end

    it "includes dashboard links" do
      expect(payload[:links]).to be_an(Array)
      expect(payload[:links].first[:href]).to include("/error_dashboard/errors/#{error_log.id}")
    end

    it "includes client info" do
      expect(payload[:client]).to eq("Rails Error Dashboard")
      expect(payload[:client_url]).to include("/error_dashboard/errors/#{error_log.id}")
    end
  end
end
