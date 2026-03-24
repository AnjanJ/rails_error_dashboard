# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::ActionCableSummary do
  def breadcrumbs_json(*crumbs)
    crumbs.to_json
  end

  def action_cable_crumb(channel:, event_type: "perform_action", action: nil)
    message = case event_type
    when "perform_action"
      action ? "perform: #{channel}##{action}" : "perform: #{channel}"
    when "transmit"
      "transmit: #{channel}"
    when "transmit_subscription_confirmation"
      "subscribed: #{channel}"
    when "transmit_subscription_rejection"
      "rejected: #{channel}"
    else
      "#{event_type}: #{channel}"
    end

    crumb = {
      "c" => "action_cable",
      "m" => message,
      "meta" => {
        "channel" => channel,
        "event_type" => event_type
      }
    }
    crumb["meta"]["action"] = action if action
    crumb
  end

  def sql_crumb(message)
    { "c" => "sql", "m" => message, "d" => 1.2 }
  end

  describe ".call" do
    it "returns empty channels when no errors exist" do
      result = described_class.call(30)
      expect(result[:channels]).to eq([])
    end

    it "returns empty channels when errors have no breadcrumbs" do
      create(:error_log, breadcrumbs: nil, occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:channels]).to eq([])
    end

    it "returns empty channels when no action_cable breadcrumbs exist" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(sql_crumb("SELECT 1")),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:channels]).to eq([])
    end

    it "extracts action_cable events from breadcrumbs" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          action_cable_crumb(channel: "ChatChannel", event_type: "perform_action", action: "speak")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:channels].size).to eq(1)

      channel = result[:channels].first
      expect(channel[:channel]).to eq("ChatChannel")
      expect(channel[:perform_count]).to eq(1)
      expect(channel[:transmit_count]).to eq(0)
      expect(channel[:rejection_count]).to eq(0)
    end

    it "groups events by channel" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          action_cable_crumb(channel: "ChatChannel", event_type: "perform_action", action: "speak"),
          action_cable_crumb(channel: "ChatChannel", event_type: "transmit"),
          action_cable_crumb(channel: "NotificationChannel", event_type: "transmit_subscription_confirmation")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:channels].size).to eq(2)

      chat = result[:channels].find { |c| c[:channel] == "ChatChannel" }
      expect(chat[:perform_count]).to eq(1)
      expect(chat[:transmit_count]).to eq(1)
      expect(chat[:total_events]).to eq(2)

      notif = result[:channels].find { |c| c[:channel] == "NotificationChannel" }
      expect(notif[:subscription_count]).to eq(1)
      expect(notif[:total_events]).to eq(1)
    end

    it "sorts by rejection count descending" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          action_cable_crumb(channel: "AdminChannel", event_type: "transmit_subscription_rejection"),
          action_cable_crumb(channel: "AdminChannel", event_type: "transmit_subscription_rejection"),
          action_cable_crumb(channel: "ChatChannel", event_type: "perform_action", action: "speak")
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:channels].first[:channel]).to eq("AdminChannel")
      expect(result[:channels].first[:rejection_count]).to eq(2)
    end

    it "counts unique errors per channel" do
      error1 = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          action_cable_crumb(channel: "ChatChannel", event_type: "perform_action")
        ),
        occurred_at: 1.day.ago)

      error2 = create(:error_log,
        breadcrumbs: breadcrumbs_json(
          action_cable_crumb(channel: "ChatChannel", event_type: "transmit")
        ),
        occurred_at: 2.days.ago)

      result = described_class.call(30)
      chat = result[:channels].first
      expect(chat[:error_count]).to eq(2)
      expect(chat[:error_ids]).to match_array([ error1.id, error2.id ])
    end

    it "respects days parameter" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          action_cable_crumb(channel: "ChatChannel", event_type: "perform_action")
        ),
        occurred_at: 60.days.ago)

      result = described_class.call(30)
      expect(result[:channels]).to eq([])
    end

    it "handles malformed breadcrumbs JSON" do
      create(:error_log, breadcrumbs: "not json", occurred_at: 1.day.ago)
      result = described_class.call(30)
      expect(result[:channels]).to eq([])
    end

    it "handles unknown event_type without incrementing type counters" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json(
          { "c" => "action_cable", "m" => "unknown: ChatChannel", "meta" => { "channel" => "ChatChannel", "event_type" => "unknown_event" } }
        ),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:channels].size).to eq(1)
      channel = result[:channels].first
      expect(channel[:perform_count]).to eq(0)
      expect(channel[:transmit_count]).to eq(0)
      expect(channel[:subscription_count]).to eq(0)
      expect(channel[:rejection_count]).to eq(0)
      expect(channel[:total_events]).to eq(0)
      expect(channel[:error_count]).to eq(1)
    end

    it "filters by application_id" do
      app1 = create(:application, name: "App1")
      app2 = create(:application, name: "App2")

      create(:error_log,
        application: app1,
        breadcrumbs: breadcrumbs_json(action_cable_crumb(channel: "ChatChannel", event_type: "perform_action")),
        occurred_at: 1.day.ago)

      create(:error_log,
        application: app2,
        breadcrumbs: breadcrumbs_json(action_cable_crumb(channel: "AdminChannel", event_type: "transmit")),
        occurred_at: 1.day.ago)

      result = described_class.call(30, application_id: app1.id)
      expect(result[:channels].size).to eq(1)
      expect(result[:channels].first[:channel]).to eq("ChatChannel")
    end

    it "handles breadcrumb with missing meta hash" do
      create(:error_log,
        breadcrumbs: breadcrumbs_json({ "c" => "action_cable", "m" => "something" }),
        occurred_at: 1.day.ago)

      result = described_class.call(30)
      expect(result[:channels].size).to eq(1)
      expect(result[:channels].first[:channel]).to eq("Unknown")
    end
  end
end
