# frozen_string_literal: true

require "rails_helper"

# Regression coverage for issue #143 — "Rack::Attack events not stored".
#
# Rack::Attack events used to be written only as breadcrumbs. Breadcrumbs are
# harvested exclusively by LogError, so an event was persisted only if an
# unrelated exception happened to be raised later in the same request. A
# throttled request returns HTTP 429 and raises nothing, so the event was always
# discarded when ErrorCatcher cleared the buffer at the end of the request.
#
# The critical assertion in this file is that a throttle event reaches the
# database when NO error occurs. Every pre-existing subscriber spec asserted
# only on the in-memory breadcrumb buffer, which is why a full suite could pass
# against a feature that had never worked.
RSpec.describe "Rack::Attack event persistence", type: :request do
  let(:subscriber) { RailsErrorDashboard::Subscribers::RackAttackSubscriber }
  let(:tracker) { RailsErrorDashboard::Services::RackAttackTracker }
  let(:event_model) { RailsErrorDashboard::RackAttackEvent }

  def fake_request(path: "/admin/users/sign_in", method: "POST", rule: "logins/ip", ip: "127.0.0.1")
    env = {
      "rack.attack.matched" => rule,
      "rack.attack.match_discriminator" => ip
    }
    instance_double(
      "Rack::Attack::Request",
      env: env,
      path: path,
      request_method: method
    )
  end

  before do
    RailsErrorDashboard.configuration.enable_rack_attack_tracking = true
    tracker.reset!
    subscriber.subscribe!
  end

  after do
    subscriber.unsubscribe!
    tracker.reset!
    RailsErrorDashboard.reset_configuration!
  end

  context "when a throttle fires and no exception is raised" do
    it "persists the event to the database" do
      ActiveSupport::Notifications.instrument(
        "throttle.rack_attack", request: fake_request
      ) { }

      expect { tracker.flush!(sync: true) }.to change(event_model, :count).by(1)

      event = event_model.last
      expect(event.rule).to eq("logins/ip")
      expect(event.match_type).to eq("throttle")
      expect(event.discriminator).to eq("127.0.0.1")
      expect(event.path).to eq("/admin/users/sign_in")
      expect(event.http_method).to eq("POST")
    end

    it "creates no error_log row" do
      ActiveSupport::Notifications.instrument(
        "throttle.rack_attack", request: fake_request
      ) { }
      tracker.flush!(sync: true)

      expect(RailsErrorDashboard::ErrorLog.count).to eq(0)
    end

    it "persists without any breadcrumb buffer present" do
      # This is the exact condition that broke the old implementation: no
      # request-scoped breadcrumb buffer, so the old code returned early.
      RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
      expect(RailsErrorDashboard::Services::BreadcrumbCollector.current_buffer).to be_nil

      ActiveSupport::Notifications.instrument(
        "throttle.rack_attack", request: fake_request
      ) { }

      expect { tracker.flush!(sync: true) }.to change(event_model, :count).by(1)
    end

    it "persists when breadcrumbs are disabled entirely" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = false

      ActiveSupport::Notifications.instrument(
        "throttle.rack_attack", request: fake_request
      ) { }

      expect { tracker.flush!(sync: true) }.to change(event_model, :count).by(1)
    end
  end

  context "reproducing the reporter's scenario" do
    # 5 login attempts, throttled after the first 3 (limit: 3).
    it "records each throttled attempt and surfaces it in the summary" do
      2.times do
        ActiveSupport::Notifications.instrument(
          "throttle.rack_attack", request: fake_request
        ) { }
      end

      tracker.flush!(sync: true)

      expect(event_model.count).to eq(1)
      expect(event_model.last.event_count).to eq(2)

      summary = RailsErrorDashboard::Queries::RackAttackSummary.call(30)
      expect(summary[:events].size).to eq(1)
      expect(summary[:events].first[:rule]).to eq("logins/ip")
      expect(summary[:events].first[:count]).to eq(2)
      expect(summary[:events].first[:unique_ips]).to eq(1)
    end
  end

  context "for blocklist and track events" do
    it "persists blocklist events" do
      ActiveSupport::Notifications.instrument(
        "blocklist.rack_attack", request: fake_request(rule: "bad_ips", ip: "10.0.0.1")
      ) { }
      tracker.flush!(sync: true)

      expect(event_model.last.match_type).to eq("blocklist")
      expect(event_model.last.rule).to eq("bad_ips")
    end

    it "persists track events" do
      ActiveSupport::Notifications.instrument(
        "track.rack_attack", request: fake_request(rule: "api_usage", ip: "user_42")
      ) { }
      tracker.flush!(sync: true)

      expect(event_model.last.match_type).to eq("track")
      expect(event_model.last.discriminator).to eq("user_42")
    end
  end

  context "when tracking is disabled" do
    it "records nothing" do
      RailsErrorDashboard.configuration.enable_rack_attack_tracking = false

      ActiveSupport::Notifications.instrument(
        "throttle.rack_attack", request: fake_request
      ) { }
      tracker.flush!(sync: true)

      expect(event_model.count).to eq(0)
    end
  end

  context "host app safety" do
    it "does not raise when the payload has no request" do
      expect {
        ActiveSupport::Notifications.instrument("throttle.rack_attack", request: nil) { }
      }.not_to raise_error
    end

    it "does not raise when the tracker itself fails" do
      allow(tracker).to receive(:record).and_raise(StandardError, "boom")

      expect {
        ActiveSupport::Notifications.instrument(
          "throttle.rack_attack", request: fake_request
        ) { }
      }.not_to raise_error
    end
  end
end
