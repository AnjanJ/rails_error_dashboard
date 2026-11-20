# frozen_string_literal: true

require "rails_helper"

# FindOrIncrementError matches a group by its v2 hash or, failing that, its v1
# hash, and moves a v1 group to v2. See .shipkit/specs/hardening-1-0-rc2
# (REQ-5, and the decision "Rows grouped under v1 keep their occurrences").
RSpec.describe RailsErrorDashboard::Commands::FindOrIncrementError, "v1 fallback" do
  let(:application) { RailsErrorDashboard::Application.find_or_create_by_name("Test App") }
  let(:v2_hash) { "2222222222222222" }
  let(:v1_hash) { "1111111111111111" }
  let(:attributes) do
    {
      application_id: application.id,
      error_type: "ArgumentError",
      message: "widget N failed",
      backtrace: "app/services/widget_service.rb:12:in 'explode'",
      occurred_at: Time.current,
      environment: "production",
      error_hash: v2_hash,
      _error_hash_v1: v1_hash
    }
  end

  after { RailsErrorDashboard::ErrorLog.delete_all }

  def seed(error_hash, **overrides)
    RailsErrorDashboard::ErrorLog.create!(
      attributes.except(:_error_hash_v1).merge(
        error_hash: error_hash,
        occurred_at: 1.hour.ago,
        first_seen_at: 1.hour.ago,
        last_seen_at: 1.hour.ago,
        occurrence_count: 3,
        resolved: false,
        status: "new",
        **overrides
      )
    )
  end

  it "moves a v1 group to v2 and counts on it (hardening-1-0-rc2/REQ-5)" do
    group = seed(v1_hash)

    result = described_class.call(v2_hash, attributes)

    expect(result.id).to eq(group.id)
    expect(group.reload.occurrence_count).to eq(4)
    expect(group.error_hash).to eq(v2_hash)
  end

  it "keeps v1 and still counts when the move hits RecordNotUnique (hardening-1-0-rc2/REQ-5)" do
    group = seed(v1_hash)
    # An open v2 row the lookups don't match (last seen over a day ago) but the
    # group-identity index does: same application, environment and window.
    stale = seed(v2_hash, occurred_at: 30.hours.ago, first_seen_at: 30.hours.ago, last_seen_at: 30.hours.ago)
    stale.update_columns(group_window: group.group_window)

    result = described_class.call(v2_hash, attributes)

    expect(result.id).to eq(group.id)
    expect(result.error_hash).to eq(v1_hash)
    expect(group.reload.occurrence_count).to eq(4)
    expect(group.error_hash).to eq(v1_hash)
    expect(stale.reload.occurrence_count).to eq(3)
    expect(RailsErrorDashboard::ErrorLog.count).to eq(2)
  end

  it "matches only the v2 hash when no v1 is given" do
    group = seed(v1_hash)

    result = described_class.call(v2_hash, attributes.except(:_error_hash_v1))

    expect(result.id).not_to eq(group.id)
    expect(group.reload.occurrence_count).to eq(3)
  end

  it "does not store the v1 hash on a new group" do
    result = described_class.call(v2_hash, attributes)

    expect(result.reload.error_hash).to eq(v2_hash)
  end
end
