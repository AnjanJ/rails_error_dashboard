# frozen_string_literal: true

require "rails_helper"

# Storm-shed events raise occurrence_count and write no ErrorOccurrence row,
# so they have a total but no timestamp. These buckets are the timestamp: one
# row per (group, hour), which is what lets a window query place shed volume.
RSpec.describe RailsErrorDashboard::EventCount do
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:flush) { RailsErrorDashboard::Commands::FlushStormCounts }

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  let(:group) do
    logs.create!(
      application_id: RailsErrorDashboard::Application.find_or_create_by_name("buckets").id,
      error_type: "StandardError", message: "bucketed", error_hash: SecureRandom.hex(8),
      occurrence_count: 0, occurred_at: Time.current, resolved: false
    )
  end

  describe ".bucket_for" do
    it "truncates to the UTC hour, so writer and reader agree" do
      expect(described_class.bucket_for(Time.utc(2026, 9, 19, 13, 47, 12)))
        .to eq(Time.utc(2026, 9, 19, 13, 0, 0))
    end
  end

  describe ".accumulate" do
    it "creates the bucket on first write and adds to it afterwards" do
      at = Time.utc(2026, 9, 19, 13, 30)

      described_class.accumulate(error_log_id: group.id, bucket_at: at, count: 5)
      described_class.accumulate(error_log_id: group.id, bucket_at: at + 10.minutes, count: 3)

      bucket = described_class.sole
      expect(bucket.bucket_at.utc).to eq(Time.utc(2026, 9, 19, 13, 0))
      expect(bucket.count).to eq(8)
    end

    it "keeps separate buckets for separate hours" do
      described_class.accumulate(error_log_id: group.id, bucket_at: Time.utc(2026, 9, 19, 13, 5), count: 2)
      described_class.accumulate(error_log_id: group.id, bucket_at: Time.utc(2026, 9, 19, 14, 5), count: 4)

      expect(described_class.order(:bucket_at).pluck(:count)).to eq([ 2, 4 ])
    end

    it "ignores a non-positive count" do
      expect(described_class.accumulate(error_log_id: group.id, bucket_at: Time.current, count: 0)).to be false
      expect(described_class.count).to eq(0)
    end

    # Transient and permanent failures are NOT the same, and treating them
    # alike is what erased time windows.
    #
    # This example previously asserted that accumulate never raises at all,
    # using StatementInvalid -- which is a RETRYABLE class. Swallowing it let
    # FlushStormCounts finalize its batch ledger with the bucket missing, so
    # the replay was suppressed as already-applied and those events vanished
    # from every window permanently while the lifetime count stayed correct.
    # Changed deliberately; see design.md F6.
    it "re-raises a transient failure so the caller can retry the batch" do
      allow(described_class).to receive(:where).and_raise(ActiveRecord::StatementInvalid, "gone")

      expect {
        described_class.accumulate(error_log_id: group.id, bucket_at: Time.current, count: 5)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    # A permanent failure still degrades quietly: retrying cannot help, and
    # failing the flush would turn a lost time bucket into a lost COUNT.
    it "returns false, without raising, on a permanent failure" do
      allow(described_class).to receive(:where).and_raise(ArgumentError, "malformed")

      expect {
        expect(described_class.accumulate(error_log_id: group.id, bucket_at: Time.current, count: 5)).to be false
      }.not_to raise_error
    end
  end

  describe "a storm flush" do
    def entry(count:, at:)
      {
        "error_class" => "StandardError",
        "message" => "shed boom",
        "first_app_frame" => "#{Rails.root}/app/models/widget.rb",
        "count" => count,
        "first_seen_at" => at.iso8601,
        "last_seen_at" => at.iso8601
      }
    end

    it "buckets the shed events it reconciles onto a new group" do
      at = Time.current.change(min: 5)

      flush.call(entries: [ entry(count: 7, at: at) ])

      row = logs.find_by(message: "shed boom")
      bucket = described_class.sole
      expect(bucket.error_log_id).to eq(row.id)
      expect(bucket.count).to eq(7)
      expect(bucket.bucket_at.utc).to eq(described_class.bucket_for(at))
    end

    it "buckets shed events added to an existing group" do
      at = Time.current.change(min: 5)
      flush.call(entries: [ entry(count: 7, at: at) ], batch_id: "b1")
      flush.call(entries: [ entry(count: 3, at: at) ], batch_id: "b2")

      expect(described_class.sum(:count)).to eq(10)
      expect(logs.find_by(message: "shed boom").occurrence_count).to eq(10)
    end
  end
end
