# frozen_string_literal: true

require "rails_helper"

# A durable table needs a cleanup path, and the comment that says it has one
# must be true.
#
# event_counts shipped with belongs_to :error_log, optional: true, no foreign
# key, no dependent option, and no reference in RetentionCleanupJob -- while
# the migration's own comment claimed "RetentionCleanupJob prunes it". Deleting
# a group left its buckets behind forever.
RSpec.describe RailsErrorDashboard::EventCount, "cleanup" do
  let(:buckets) { described_class }

  before { RailsErrorDashboard.reset_configuration! }
  after  { RailsErrorDashboard.reset_configuration! }

  def group_with_bucket(occurred_at: Time.current)
    log = create(:error_log, occurred_at: occurred_at, last_seen_at: occurred_at)
    described_class.accumulate(error_log_id: log.id, bucket_at: occurred_at, count: 5)
    expect(buckets.where(error_log_id: log.id)).to exist
    log
  end

  it "removes buckets when the group is destroyed" do
    log = group_with_bucket

    log.destroy

    expect(buckets.where(error_log_id: log.id)).to be_empty
  end

  it "removes buckets when retention expires the group" do
    RailsErrorDashboard.configuration.retention_days = 30
    log = group_with_bucket(occurred_at: 90.days.ago)
    log.update_columns(last_seen_at: 90.days.ago, created_at: 90.days.ago)

    removed = RailsErrorDashboard::RetentionCleanupJob.perform_now

    expect(removed).to be >= 1
    expect(buckets.where(error_log_id: log.id)).to be_empty
  end

  it "leaves buckets of still-active groups alone" do
    RailsErrorDashboard.configuration.retention_days = 30
    keep = group_with_bucket(occurred_at: 1.day.ago)
    keep.update_columns(last_seen_at: 1.day.ago)

    RailsErrorDashboard::RetentionCleanupJob.perform_now

    expect(buckets.where(error_log_id: keep.id)).to exist
  end
end
