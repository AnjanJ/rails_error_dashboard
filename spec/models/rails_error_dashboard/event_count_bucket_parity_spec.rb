# frozen_string_literal: true

require "rails_helper"

# The producer (CountBuffer) and the storage (EventCount) must share ONE bucket
# definition. They did not: CountBuffer tallied 15-minute buckets precisely so
# a local midnight would fall on a bucket EDGE, and EventCount.bucket_for then
# rounded every one of them to the hour -- which is the exact rounding the
# 15-minute choice existed to avoid. Two storm events straddling midnight in
# Kolkata were stored in one bucket and both landed on yesterday.
RSpec.describe RailsErrorDashboard::EventCount, "bucket parity with the producer" do
  Producer = RailsErrorDashboard::Services::StormProtection::CountBuffer

  it "uses the same bucket width as the producer" do
    expect(described_class::BUCKET_SECONDS).to eq(Producer::BUCKET_SECONDS)
  end

  it "agrees with the producer on which bucket an instant belongs to" do
    instant = Time.utc(2026, 9, 19, 18, 37, 42)

    expect(described_class.bucket_for(instant).to_i).to eq(Producer.bucket_for(instant))
  end

  # The two offsets the producer's comment names by hand.
  { "Asia/Kolkata" => "+05:30", "Asia/Kathmandu" => "+05:45" }.each do |zone, offset|
    it "places a local midnight on a bucket edge in #{zone} (#{offset})" do
      midnight = ActiveSupport::TimeZone[zone].parse("2026-09-20 00:00:00")

      expect(described_class.bucket_for(midnight)).to eq(midnight)
    end

    it "keeps events either side of local midnight in different buckets in #{zone}" do
      zone_obj = ActiveSupport::TimeZone[zone]
      before = zone_obj.parse("2026-09-19 23:59:30")
      after  = zone_obj.parse("2026-09-20 00:00:30")

      expect(described_class.bucket_for(before)).not_to eq(described_class.bucket_for(after))
    end
  end

  it "separates a midnight-straddling storm across days end to end" do
    zone_obj = ActiveSupport::TimeZone["Asia/Kolkata"]
    group = RailsErrorDashboard::ErrorLog.create!(
      application_id: RailsErrorDashboard::Application.find_or_create_by_name("straddle").id,
      error_type: "StormError", message: "straddle",
      error_hash: "straddle-#{SecureRandom.hex(6)}",
      occurred_at: zone_obj.parse("2026-09-19 12:00:00"), occurrence_count: 2,
      resolved: false
    )

    described_class.accumulate(error_log_id: group.id,
                               bucket_at: zone_obj.parse("2026-09-19 23:59:30"), count: 1)
    described_class.accumulate(error_log_id: group.id,
                               bucket_at: zone_obj.parse("2026-09-20 00:00:30"), count: 1)

    days = described_class.where(error_log_id: group.id)
                          .pluck(:bucket_at)
                          .map { |t| t.in_time_zone(zone_obj).to_date }

    expect(days.uniq.size).to eq(2)
  end
end
