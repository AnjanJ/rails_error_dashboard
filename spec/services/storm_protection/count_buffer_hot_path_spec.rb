# frozen_string_literal: true

require "rails_helper"

# storm-gate-hot-path/REQ-4: counting a fingerprint the buffer already holds
# is the hot path of a storm in count-only mode, so it builds no
# TimeWithZone and no per-event hash, and the parts are built only on insert.
RSpec.describe RailsErrorDashboard::Services::StormProtection::CountBuffer, "hot path" do
  let(:buffer) { described_class.new }
  let(:parts) do
    {
      error_class: "NoMethodError", message: "undefined method 'boom'", first_app_frame: "/app/models/user.rb",
      controller_name: "users", action_name: "show", custom_hash: nil, environment: "production",
      opaque_identity: "abc123", capture_source: "server"
    }
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "counts a known key without Time.current or calling for the parts again (storm-gate-hot-path/REQ-4)" do
    buffer.record("key1") { parts }
    allow(Time).to receive(:current).and_call_original

    buffer.record("key1") { raise "the parts were built for a key the buffer already holds" }
    buffer.record("key1", parts)

    expect(Time).not_to have_received(:current)
    expect(buffer.snapshot![:entries].first["count"]).to eq(3)
  end

  it "builds the parts exactly once, when the key is new (storm-gate-hot-path/REQ-4)" do
    built = 0

    3.times { buffer.record("key1") { built += 1; parts } }

    expect(built).to eq(1)
  end

  it "counts into the overflow without building parts when the map is full (storm-gate-hot-path/REQ-4)" do
    RailsErrorDashboard.configuration.storm_max_tracked_fingerprints = 1
    buffer.record("key1", parts)

    buffer.record("key2") { raise "the parts were built for an event that only lands in the overflow" }

    expect(buffer.snapshot![:overflow]).to eq(1)
  end

  it "snapshots exactly what 0.17.0 did: counts, buckets and times in Time.zone (storm-gate-hot-path/REQ-4)" do
    started = Time.utc(2026, 10, 30, 9, 10, 0)
    later = started + 20.minutes # the next 15-minute bucket
    # The process zone must differ from Time.zone, or a time formatted in the
    # wrong one would still read +05:30 (on a machine set to India, say).
    original_tz = ENV["TZ"]
    ENV["TZ"] = "UTC"

    Time.use_zone("Asia/Kolkata") do
      travel_to(started) { 2.times { buffer.record("key1") { parts } } }
      travel_to(later) { buffer.record("key1") { parts } }

      entry = buffer.snapshot![:entries].first

      expect(entry).to include(
        "count" => 3,
        "first_seen_at" => "2026-10-30T14:40:00+05:30",
        "last_seen_at" => "2026-10-30T15:00:00+05:30",
        "buckets" => {
          described_class.bucket_for(started).to_s => 2,
          described_class.bucket_for(later).to_s => 1
        },
        "message" => "undefined method 'boom'",
        "opaque_identity" => "abc123",
        "environment" => "production"
      )
    end
  ensure
    ENV["TZ"] = original_tz
  end
end
