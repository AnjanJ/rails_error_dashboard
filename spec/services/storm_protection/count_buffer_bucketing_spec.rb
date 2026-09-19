# frozen_string_literal: true

require "rails_helper"

# Timing discarded by the PRODUCER cannot be recovered by the consumer.
#
# CountBuffer kept one total per fingerprint plus first/last timestamps, and
# FlushStormCounts assigned that whole total to the bucket containing
# last_seen_at. One event at 23:59:59 and another at 00:00:01 therefore became
# two events today and none yesterday -- the per-bucket table introduced for
# exactly this purpose could not help, because the number it was given had
# already been collapsed.
#
# Buckets are 15 minutes so that every supported UTC offset -- including
# +05:30 and +05:45 -- has its local midnight fall on a bucket edge.
RSpec.describe RailsErrorDashboard::Services::StormProtection::CountBuffer, "bucketing" do
  subject(:buffer) { described_class.new }

  let(:parts) do
    {
      error_class: "StandardError", message: "bucket boom",
      first_app_frame: "/app/models/order.rb", controller_name: nil,
      action_name: nil, custom_hash: nil, environment: nil,
      opaque_identity: "same-fingerprint"
    }
  end

  def record_at(time)
    travel_to(time) { buffer.record("same-fingerprint", parts) }
  end

  it "keeps events on either side of midnight in separate buckets" do
    record_at(Time.zone.parse("2026-09-18 23:59:59"))
    record_at(Time.zone.parse("2026-09-19 00:00:01"))

    entries = buffer.snapshot!.fetch(:entries)
    buckets = entries.flat_map { |e| e["buckets"].to_a }

    expect(buckets.sum { |_at, n| n }).to eq(2)
    expect(buckets.size).to eq(2), "expected two distinct buckets, got #{buckets.inspect}"
  end

  it "uses 15-minute buckets, so a +05:30 local midnight is a bucket edge" do
    record_at(Time.zone.parse("2026-09-19 18:29:59")) # 23:59:59 IST
    record_at(Time.zone.parse("2026-09-19 18:30:01")) # 00:00:01 IST next day

    entries = buffer.snapshot!.fetch(:entries)
    buckets = entries.flat_map { |e| e["buckets"].to_a }

    expect(buckets.size).to eq(2),
      "a +05:30 midnight must fall on a bucket edge; got #{buckets.inspect}"
  end

  it "merges repeat events within one bucket" do
    record_at(Time.zone.parse("2026-09-19 10:00:01"))
    record_at(Time.zone.parse("2026-09-19 10:14:59"))

    entries = buffer.snapshot!.fetch(:entries)
    buckets = entries.flat_map { |e| e["buckets"].to_a }

    expect(buckets.size).to eq(1)
    expect(buckets.sum { |_at, n| n }).to eq(2)
  end

  it "carries buckets through a failed handoff and back" do
    record_at(Time.zone.parse("2026-09-18 23:59:59"))
    record_at(Time.zone.parse("2026-09-19 00:00:01"))

    snapshot = buffer.snapshot!
    buffer.restore(snapshot[:entries], snapshot[:overflow])

    restored = buffer.snapshot!.fetch(:entries).flat_map { |e| e["buckets"].to_a }

    expect(restored.sum { |_at, n| n }).to eq(2)
    expect(restored.size).to eq(2), "restore() dropped the per-bucket split"
  end

  it "still counts overflow beyond the fingerprint cap" do
    allow(RailsErrorDashboard.configuration).to receive(:storm_max_tracked_fingerprints).and_return(1)

    travel_to(Time.zone.parse("2026-09-19 10:00:00")) do
      buffer.record("first", parts)
      buffer.record("second", parts.merge(opaque_identity: "other"))
    end

    snapshot = buffer.snapshot!
    expect(snapshot[:overflow]).to eq(1)
  end
end
