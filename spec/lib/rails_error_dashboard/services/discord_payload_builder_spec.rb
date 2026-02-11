# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::DiscordPayloadBuilder do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "RuntimeError",
      message: "Something went wrong",
      controller_name: "posts",
      action_name: "create",
      platform: "API",
      occurrence_count: 5,
      backtrace: "app/models/post.rb:10:in `save'\napp/controllers/posts_controller.rb:20")
  end

  describe ".call" do
    subject(:payload) { described_class.call(error_log) }

    it "returns a hash with embeds array" do
      expect(payload).to be_a(Hash)
      expect(payload[:embeds]).to be_an(Array)
      expect(payload[:embeds].length).to eq(1)
    end

    it "includes error type in title" do
      expect(payload[:embeds].first[:title]).to include("RuntimeError")
    end

    it "includes message as description" do
      expect(payload[:embeds].first[:description]).to include("Something went wrong")
    end

    it "includes platform field" do
      fields = payload[:embeds].first[:fields]
      platform_field = fields.find { |f| f[:name] == "Platform" }
      expect(platform_field[:value]).to eq("API")
    end

    it "includes occurrence count" do
      fields = payload[:embeds].first[:fields]
      count_field = fields.find { |f| f[:name] == "Occurrences" }
      expect(count_field[:value]).to eq("5")
    end

    it "includes controller and action" do
      fields = payload[:embeds].first[:fields]
      expect(fields.find { |f| f[:name] == "Controller" }[:value]).to eq("posts")
      expect(fields.find { |f| f[:name] == "Action" }[:value]).to eq("create")
    end

    it "includes backtrace location" do
      fields = payload[:embeds].first[:fields]
      location = fields.find { |f| f[:name] == "Location" }
      expect(location[:value]).to include("app/models/post.rb")
    end

    it "includes footer" do
      expect(payload[:embeds].first[:footer][:text]).to eq("Rails Error Dashboard")
    end

    it "includes ISO 8601 timestamp" do
      expect(payload[:embeds].first[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe ".severity_color" do
    it "returns correct colors" do
      expect(described_class.severity_color(double(severity: :critical))).to eq(16711680)
      expect(described_class.severity_color(double(severity: :high))).to eq(16744192)
      expect(described_class.severity_color(double(severity: :medium))).to eq(16776960)
      expect(described_class.severity_color(double(severity: :low))).to eq(8421504)
    end
  end
end
