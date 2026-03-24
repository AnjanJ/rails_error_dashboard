# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Subscribers::ActionCableSubscriber do
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  before do
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    collector.init_buffer
  end

  after do
    described_class.unsubscribe!
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  describe ".subscribe!" do
    it "registers all expected event subscribers" do
      subscriptions = described_class.subscribe!
      expect(subscriptions).to be_an(Array)
      expect(subscriptions.size).to eq(4)
    end

    it "stores subscriptions for later cleanup" do
      described_class.subscribe!
      expect(described_class.subscriptions).not_to be_empty
    end
  end

  describe ".unsubscribe!" do
    it "removes all subscriptions" do
      described_class.subscribe!
      expect(described_class.subscriptions).not_to be_empty

      described_class.unsubscribe!
      expect(described_class.subscriptions).to be_empty
    end
  end

  describe "perform_action.action_cable subscriber" do
    before { described_class.subscribe! }

    it "adds action_cable breadcrumb with perform details" do
      ActiveSupport::Notifications.instrument("perform_action.action_cable", {
        channel_class: "ChatChannel",
        action: "speak",
        data: { message: "hello" }
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty

      crumb = ac_crumbs.last
      expect(crumb[:m]).to eq("perform: ChatChannel#speak")
      expect(crumb[:meta][:channel]).to eq("ChatChannel")
      expect(crumb[:meta][:event_type]).to eq("perform_action")
      expect(crumb[:meta][:action]).to eq("speak")
    end

    it "handles missing action gracefully" do
      ActiveSupport::Notifications.instrument("perform_action.action_cable", {
        channel_class: "ChatChannel"
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty
      expect(ac_crumbs.last[:m]).to eq("perform: ChatChannel")
    end
  end

  describe "transmit.action_cable subscriber" do
    before { described_class.subscribe! }

    it "adds action_cable breadcrumb with transmit details" do
      ActiveSupport::Notifications.instrument("transmit.action_cable", {
        channel_class: "NotificationChannel",
        data: { count: 5 },
        via: "streamed from notifications"
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty

      crumb = ac_crumbs.last
      expect(crumb[:m]).to eq("transmit: NotificationChannel")
      expect(crumb[:meta][:channel]).to eq("NotificationChannel")
      expect(crumb[:meta][:event_type]).to eq("transmit")
    end
  end

  describe "transmit_subscription_confirmation.action_cable subscriber" do
    before { described_class.subscribe! }

    it "adds action_cable breadcrumb with subscription confirmation" do
      ActiveSupport::Notifications.instrument("transmit_subscription_confirmation.action_cable", {
        channel_class: "AppearanceChannel"
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty

      crumb = ac_crumbs.last
      expect(crumb[:m]).to eq("subscribed: AppearanceChannel")
      expect(crumb[:meta][:channel]).to eq("AppearanceChannel")
      expect(crumb[:meta][:event_type]).to eq("transmit_subscription_confirmation")
    end
  end

  describe "transmit_subscription_rejection.action_cable subscriber" do
    before { described_class.subscribe! }

    it "adds action_cable breadcrumb with subscription rejection" do
      ActiveSupport::Notifications.instrument("transmit_subscription_rejection.action_cable", {
        channel_class: "AdminChannel"
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty

      crumb = ac_crumbs.last
      expect(crumb[:m]).to eq("rejected: AdminChannel")
      expect(crumb[:meta][:channel]).to eq("AdminChannel")
      expect(crumb[:meta][:event_type]).to eq("transmit_subscription_rejection")
    end
  end

  describe "channel key fallback" do
    before { described_class.subscribe! }

    it "uses :channel key when :channel_class is absent" do
      ActiveSupport::Notifications.instrument("transmit_subscription_confirmation.action_cable", {
        channel: "AppearanceChannel"
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs.last[:meta][:channel]).to eq("AppearanceChannel")
    end

    it "prefers :channel_class over :channel" do
      ActiveSupport::Notifications.instrument("transmit.action_cable", {
        channel_class: "ChatChannel",
        channel: "OtherChannel"
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs.last[:meta][:channel]).to eq("ChatChannel")
    end
  end

  describe "duration capture" do
    before { described_class.subscribe! }

    it "captures duration for perform_action events" do
      ActiveSupport::Notifications.instrument("perform_action.action_cable", {
        channel_class: "ChatChannel",
        action: "speak"
      }) { sleep 0.001 }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs.last[:d]).to be_a(Numeric)
      expect(ac_crumbs.last[:d]).to be >= 0
    end
  end

  describe "safety" do
    before { described_class.subscribe! }

    it "skips when no breadcrumb buffer is active" do
      collector.clear_buffer

      ActiveSupport::Notifications.instrument("perform_action.action_cable", {
        channel_class: "ChatChannel",
        action: "speak"
      }) { }

      # Re-init buffer to check — nothing should have been added
      collector.init_buffer
      breadcrumbs = collector.harvest
      expect(breadcrumbs.select { |c| c[:c] == "action_cable" }).to be_empty
    end

    it "handles empty payload gracefully" do
      ActiveSupport::Notifications.instrument("perform_action.action_cable", {}) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty
      expect(ac_crumbs.last[:meta][:channel]).to eq("Unknown")
    end

    it "handles nil payload values gracefully" do
      ActiveSupport::Notifications.instrument("transmit.action_cable", {
        channel_class: nil,
        data: nil
      }) { }

      breadcrumbs = collector.harvest
      ac_crumbs = breadcrumbs.select { |c| c[:c] == "action_cable" }
      expect(ac_crumbs).not_to be_empty
      expect(ac_crumbs.last[:m]).to eq("transmit: Unknown")
    end
  end
end
