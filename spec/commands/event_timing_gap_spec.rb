# frozen_string_literal: true

require "rails_helper"

# The completeness warning must survive three things the earlier designs did not.
#
# All three are structural, not incidental:
#   1. The storm EPISODE is optional -- the gate can shed with its breaker
#      closed and pass episode: nil -- so a flag on the episode vanished
#      exactly when no episode existed.
#   2. upsert_storm_event runs AFTER the counts transaction commits and
#      rescues its own failures, so a transient save failure lost the marker
#      while the ledger already recorded the batch as applied. The replay was
#      then suppressed and the gap was never recorded at all.
#   3. The dashboard shows today, 7-day and 30-day figures. A predicate that
#      only asks about today drops the warning while the wider windows still
#      contain the affected events.
RSpec.describe "event timing gap recording" do
  # Clock pinned to MIDDAY for every example.
  #
  # These fixtures use minute-scale offsets against day-boundary queries, so on
  # a real clock they depend on the time of day -- the same latent defect that
  # made the volume invariants fail only near midnight (expected 15, got 3).
  # Midday leaves a twelve-hour margin either side.
  #
  # `travel_to` in a before hook rather than an `around`: several examples
  # below travel again themselves, and Rails rejects a nested travel_to.
  # TimeHelpers unstubs automatically after each example.
  before { travel_to(Time.zone.parse("2026-09-15 12:00:00")) }

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    Rails.cache.clear
    allow(RailsErrorDashboard::EventCount).to receive(:table_exists?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  let(:identity) { "gap-#{SecureRandom.hex(6)}" }

  def entry
    {
      "error_class" => "StormError", "message" => identity,
      "count" => 10, "opaque_identity" => identity,
      "first_seen_at" => 5.minutes.ago.iso8601, "last_seen_at" => Time.current.iso8601
    }
  end

  def flush(episode: nil, batch_id: SecureRandom.hex(8))
    RailsErrorDashboard::Commands::FlushStormCounts.call(
      entries: [ entry ], episode: episode, batch_id: batch_id
    )
  end

  describe "without any storm episode" do
    it "still records the gap" do
      expect { flush(episode: nil) }.to change { RailsErrorDashboard::EventTimingGap.count }.by(1)
    end

    it "still warns on the dashboard" do
      flush(episode: nil)
      Rails.cache.clear

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be(true)
    end

    it "records how many events lost their timing" do
      flush(episode: nil)

      expect(RailsErrorDashboard::EventTimingGap.last.events_affected).to eq(10)
    end
  end

  describe "atomicity with the counts" do
    # The gap is written inside the SAME transaction as the counts, so the two
    # cannot disagree. If the gap cannot be written, the counts roll back too
    # and the batch stays replayable -- rather than committing counts whose
    # unreliability is unrecorded.
    it "rolls the counts back when the gap cannot be recorded" do
      allow(RailsErrorDashboard::EventTimingGap).to receive(:create!)
        .and_raise(ActiveRecord::StatementInvalid, "gap write failed")

      expect { flush(episode: nil) }
        .not_to change { RailsErrorDashboard::ErrorLog.where(error_type: "StormError").count }
    end

    it "leaves the batch replayable rather than silently applied" do
      call_count = 0
      allow(RailsErrorDashboard::EventTimingGap).to receive(:create!).and_wrap_original do |orig, *args|
        call_count += 1
        raise ActiveRecord::StatementInvalid, "transient" if call_count == 1

        orig.call(*args)
      end

      batch = SecureRandom.hex(8)
      flush(episode: nil, batch_id: batch)   # fails, rolls back
      flush(episode: nil, batch_id: batch)   # replay must actually apply

      expect(RailsErrorDashboard::EventTimingGap.count).to eq(1)
      expect(RailsErrorDashboard::ErrorLog.where(error_type: "StormError")
               .where("message LIKE ?", "%#{identity}%").sum(:occurrence_count)).to eq(10)
    end
  end

  describe "the windows the dashboard actually displays" do
    # A gap from three days ago no longer overlaps "today", but the 7-day and
    # 30-day figures on the same page still include those events.
    before do
      travel_to(3.days.ago) { flush(episode: nil) }
      Rails.cache.clear
    end

    it "still warns while the weekly and monthly figures include the events" do
      stats = RailsErrorDashboard::Queries::DashboardStats.call

      expect(stats[:total_month]).to be > 0
      expect(stats[:event_timing_incomplete]).to be(true)
    end

    it "stops warning once no displayed window reaches the gap" do
      travel_to(40.days.from_now) do
        Rails.cache.clear
        expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be_falsey
      end
    end
  end

  describe "when buckets are writable" do
    before { allow(RailsErrorDashboard::EventCount).to receive(:table_exists?).and_call_original }

    it "records no gap" do
      expect { flush(episode: nil) }.not_to change { RailsErrorDashboard::EventTimingGap.count }
    end

    it "does not warn" do
      flush(episode: nil)
      Rails.cache.clear

      expect(RailsErrorDashboard::Queries::DashboardStats.call[:event_timing_incomplete]).to be_falsey
    end
  end
end

# A gap has no error_log_id to cascade from, so retention has to prune it by
# its own age or the table grows for the life of the installation.
RSpec.describe RailsErrorDashboard::RetentionCleanupJob, "timing gap pruning" do
  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.retention_days = 30
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "deletes gaps older than the retention cutoff" do
    old = RailsErrorDashboard::EventTimingGap.create!(
      covered_from: 90.days.ago, covered_until: 89.days.ago, events_affected: 1
    )

    described_class.perform_now

    expect(RailsErrorDashboard::EventTimingGap.where(id: old.id)).not_to exist
  end

  it "keeps gaps still inside the retention window" do
    recent = RailsErrorDashboard::EventTimingGap.create!(
      covered_from: 2.days.ago, covered_until: 2.days.ago, events_affected: 1
    )

    described_class.perform_now

    expect(RailsErrorDashboard::EventTimingGap.where(id: recent.id)).to exist
  end
end
