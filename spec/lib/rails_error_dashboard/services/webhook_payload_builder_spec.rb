# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::WebhookPayloadBuilder do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "ArgumentError",
      message: "wrong number of arguments",
      controller_name: "orders",
      action_name: "create",
      platform: "API",
      occurrence_count: 3,
      request_url: "http://example.com/orders",
      user_agent: "Mozilla/5.0",
      ip_address: "10.0.0.1",
      backtrace: "app/services/order_service.rb:25\napp/controllers/orders_controller.rb:12")
  end

  describe ".call" do
    subject(:payload) { described_class.call(error_log) }

    it "sets event to error.created" do
      expect(payload[:event]).to eq("error.created")
    end

    it "includes ISO 8601 timestamp" do
      expect(payload[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it "includes error details" do
      error = payload[:error]
      expect(error[:id]).to eq(error_log.id)
      expect(error[:type]).to eq("ArgumentError")
      expect(error[:message]).to eq("wrong number of arguments")
      expect(error[:platform]).to eq("API")
      expect(error[:controller]).to eq("orders")
      expect(error[:action]).to eq("create")
      expect(error[:occurrence_count]).to eq(3)
    end

    it "includes request info" do
      request = payload[:error][:request]
      expect(request[:url]).to eq("http://example.com/orders")
      expect(request[:user_agent]).to eq("Mozilla/5.0")
      expect(request[:ip_address]).to eq("10.0.0.1")
    end

    it "includes user info" do
      expect(payload[:error][:user][:id]).to eq(error_log.user_id)
    end

    it "includes backtrace as array" do
      expect(payload[:error][:backtrace]).to be_an(Array)
      expect(payload[:error][:backtrace].first).to include("order_service.rb")
    end

    it "includes metadata with hash and dashboard URL" do
      metadata = payload[:error][:metadata]
      expect(metadata[:error_hash]).to eq(error_log.error_hash)
      expect(metadata[:dashboard_url]).to include("/error_dashboard/errors/#{error_log.id}")
    end

    it "includes resolved status" do
      expect(payload[:error][:resolved]).to eq(error_log.resolved)
    end
  end
end
