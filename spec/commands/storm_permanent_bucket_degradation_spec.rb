# frozen_string_literal: true

require "rails_helper"

# Permanent bucket unavailability must DEGRADE, not destroy.
#
# EventCount.accumulate returns false for a permanent outcome (no rollup table,
# an adapter that refuses the statement). The caller turned every false into an
# EventCountWriteFailed, which aborted the surrounding transaction and rolled
# back the lifetime occurrence_count too -- so a host that never migrated the
# rollup table lost its counts entirely. The authoritative total is
# occurrence_count on the group, and it is written independently of the bucket.
RSpec.describe RailsErrorDashboard::Commands::FlushStormCounts, "permanent bucket unavailability" do
  before do
    allow(RailsErrorDashboard::EventCount).to receive(:table_exists?).and_return(false)
  end

  # batch_id varies per flush: the batch-digest ledger suppresses an identical
  # replay by design, so a fixture that reused one would measure idempotency
  # rather than degradation.
  def flush_five(batch_id: SecureRandom.hex(8))
    described_class.call(
      entries: [
        {
          "error_class" => "StormError", "message" => "degrade",
          "count" => 5, "opaque_identity" => "degrade-fixture",
          "first_seen_at" => 10.minutes.ago.iso8601, "last_seen_at" => Time.current.iso8601
        }
      ],
      batch_id: batch_id
    )
  end

  it "still commits the lifetime count when buckets are permanently unavailable" do
    result = flush_five

    expect(result[:success]).to be(true)
    expect(RailsErrorDashboard::ErrorLog.sum(:occurrence_count)).to eq(5)
  end

  it "does not lose counts across repeated flushes" do
    3.times { flush_five }

    expect(RailsErrorDashboard::ErrorLog.sum(:occurrence_count)).to eq(15)
  end

  it "reports that the time-window evidence is incomplete" do
    expect(flush_five[:buckets_incomplete]).to be(true)
  end

  it "does not claim incompleteness when buckets are writable" do
    allow(RailsErrorDashboard::EventCount).to receive(:table_exists?).and_call_original

    expect(flush_five[:buckets_incomplete]).to be_falsey
  end
end
