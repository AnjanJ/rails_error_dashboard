# frozen_string_literal: true

require "rails_helper"

# A transient bucket-write failure must not finalize the batch.
#
# EventCount.accumulate rescued every StandardError and returned false;
# FlushStormCounts ignored that return value and committed its ledger. The
# lifetime count stayed correct and the TIME WINDOW was erased permanently:
# the replay saw already_applied and did nothing.
RSpec.describe RailsErrorDashboard::Commands::FlushStormCounts, "bucket write failures" do
  let(:buckets) { RailsErrorDashboard::EventCount }

  before do
    RailsErrorDashboard.reset_configuration!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  def entry(count:, at:, id: "bucket-failure")
    {
      "error_class" => "StandardError",
      "message" => "bucket failure boom",
      "first_app_frame" => "#{Rails.root}/app/models/order.rb",
      "opaque_identity" => id,
      "count" => count,
      "first_seen_at" => at.iso8601,
      "last_seen_at" => at.iso8601,
      "buckets" => { RailsErrorDashboard::Services::StormProtection::CountBuffer.bucket_for(at).to_s => count }
    }
  end

  it "aborts the batch and leaves it replayable when a bucket write is transient" do
    at = Time.current
    payload = [ entry(count: 5, at: at) ]

    call_count = 0
    allow(RailsErrorDashboard::EventCount).to receive(:accumulate).and_wrap_original do |original, **kwargs|
      call_count += 1
      raise ActiveRecord::ConnectionNotEstablished, "synthetic" if call_count == 1

      original.call(**kwargs)
    end

    first = described_class.call(entries: payload, batch_id: "bucket-fail-1")

    expect(first[:success]).to be(false)
    expect(first[:retryable]).to be(true)
    expect(RailsErrorDashboard::ErrorLog.sum(:occurrence_count)).to eq(0),
      "the batch must roll back entirely, counts included"

    replay = described_class.call(entries: payload, batch_id: "bucket-fail-1")

    expect(replay[:success]).to be(true)
    expect(replay[:already_applied]).to be_nil
    expect(RailsErrorDashboard::ErrorLog.sum(:occurrence_count)).to eq(5)
    expect(buckets.sum(:count)).to eq(5), "the time window must be recovered by the replay"
  end

  it "writes one row per bucket when a batch straddles a boundary" do
    before_midnight = Time.zone.parse("2026-09-18 23:59:59")
    after_midnight  = Time.zone.parse("2026-09-19 00:00:01")

    straddling = [ {
      "error_class" => "StandardError",
      "message" => "straddle boom",
      "first_app_frame" => "#{Rails.root}/app/models/order.rb",
      "opaque_identity" => "straddle",
      "count" => 2,
      "first_seen_at" => before_midnight.iso8601,
      "last_seen_at" => after_midnight.iso8601,
      "buckets" => {
        RailsErrorDashboard::Services::StormProtection::CountBuffer.bucket_for(before_midnight).to_s => 1,
        RailsErrorDashboard::Services::StormProtection::CountBuffer.bucket_for(after_midnight).to_s => 1
      }
    } ]

    described_class.call(entries: straddling, batch_id: "straddle-1")

    expect(buckets.count).to eq(2), "expected a row per bucket, got #{buckets.pluck(:bucket_at, :count).inspect}"
    expect(buckets.sum(:count)).to eq(2)
  end

  # A payload from a release that predates bucketing must still reconcile.
  it "falls back to last_seen_at when the payload carries no buckets" do
    at = Time.zone.parse("2026-09-19 10:00:00")
    legacy = [ entry(count: 3, at: at).except("buckets") ]

    result = described_class.call(entries: legacy, batch_id: "legacy-1")

    expect(result[:success]).to be(true)
    expect(buckets.sum(:count)).to eq(3)
  end
end
