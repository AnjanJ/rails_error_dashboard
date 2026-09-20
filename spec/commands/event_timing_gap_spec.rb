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

# Completeness evidence has to outlive the SHORTER of the two clocks that
# govern it, not just one of them.
#
# Gap cleanup used the configured retention_days, while the Overview reads gaps
# against a 30-day window. With retention_days = 7 the gap was deleted while the
# events it qualified were still on the page: ten monthly events, no warning,
# group still active. Only settings BELOW the reporting window are affected --
# the 90-day default and a 30-day setting both behave correctly, which is why
# this survived the original pruning spec.
RSpec.describe RailsErrorDashboard::RetentionCleanupJob, "timing gaps under short retention" do
  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  # Active today, so retention keeps the group; its gap is older than a short
  # retention window but still inside the reporting window.
  def active_group_with_old_gap
    app = RailsErrorDashboard::Application.find_or_create_by_name("retention-horizon")
    group = RailsErrorDashboard::ErrorLog.create!(
      application_id: app.id, error_type: "StormError", message: "still active",
      error_hash: SecureRandom.hex(8), occurrence_count: 10,
      occurred_at: 10.days.ago, last_seen_at: Time.current, resolved: false
    )
    gap = RailsErrorDashboard::EventTimingGap.create!(
      covered_from: 10.days.ago, covered_until: 10.days.ago, events_affected: 5
    )
    [ group, gap ]
  end

  context "when retention is shorter than the reporting window" do
    before { RailsErrorDashboard.configuration.retention_days = 7 }

    it "keeps the gap while its events are still displayed" do
      _group, gap = active_group_with_old_gap

      described_class.perform_now

      expect(RailsErrorDashboard::EventTimingGap.where(id: gap.id)).to exist
    end

    it "keeps warning about the events it still shows" do
      active_group_with_old_gap

      described_class.perform_now
      Rails.cache.clear
      stats = RailsErrorDashboard::Queries::DashboardStats.call

      expect(stats[:total_month]).to be > 0
      expect(stats[:event_timing_incomplete]).to be(true)
    end
  end

  # Retaining a gap past its own retention means it can outlive every event it
  # covered, because expiring the GROUP is what removes those events. A banner
  # qualifying a window that shows nothing is noise, and noise trains people to
  # ignore the banner.
  context "when the events themselves are gone" do
    before { RailsErrorDashboard.configuration.retention_days = 7 }

    it "does not warn about an empty window" do
      RailsErrorDashboard::EventTimingGap.create!(
        covered_from: 10.days.ago, covered_until: 10.days.ago, events_affected: 5
      )

      described_class.perform_now
      Rails.cache.clear
      stats = RailsErrorDashboard::Queries::DashboardStats.call

      expect(stats[:total_month]).to eq(0)
      expect(stats[:event_timing_incomplete]).to be_falsey
    end

    # The other half of the same predicate, and the one the first version got
    # wrong: a zero window total is ALSO what a group whose timing was lost
    # looks like, so zero cannot be read as "nothing happened".
    #
    # A group first seen outside the window that recurs inside it is invisible
    # to the aggregate by construction -- EventVolume can only place an
    # untracked remainder at the group's own occurred_at, which precedes the
    # window -- so the events are real, the group is alive, and every displayed
    # figure is zero. Suppressing here is silence in exactly the state the
    # banner exists to announce (see F24).
    it "warns when the window total is zero because the timing itself was lost" do
      app = RailsErrorDashboard::Application.find_or_create_by_name("zero-volume-gap")
      group = RailsErrorDashboard::ErrorLog.create!(
        application_id: app.id, error_type: "StormError", message: "recurred untimed",
        error_hash: SecureRandom.hex(8), occurrence_count: 10,
        occurred_at: 60.days.ago, resolved: false
      )
      # last_seen_at is stamped on create, so set the recurrence explicitly.
      group.update_column(:last_seen_at, Time.current)
      RailsErrorDashboard::EventTimingGap.create!(
        application_id: app.id, covered_from: Time.current, covered_until: Time.current,
        events_affected: 5
      )

      Rails.cache.clear
      stats = RailsErrorDashboard::Queries::DashboardStats.call

      # The aggregate genuinely cannot see the events; the banner must anyway.
      expect(stats[:total_month]).to eq(0)
      expect(stats[:event_timing_incomplete]).to be(true)
    end

    # The suppression must key on group liveness, not on gap age: the orphan
    # example above uses a gap only ten days old, well inside the window, so
    # "old gap" cannot be the discriminator.
    it "does not warn when the only group expired before the window" do
      app = RailsErrorDashboard::Application.find_or_create_by_name("expired-group-gap")
      group = RailsErrorDashboard::ErrorLog.create!(
        application_id: app.id, error_type: "StormError", message: "long gone",
        error_hash: SecureRandom.hex(8), occurrence_count: 3,
        occurred_at: 200.days.ago, resolved: false
      )
      group.update_column(:last_seen_at, 200.days.ago)
      RailsErrorDashboard::EventTimingGap.create!(
        covered_from: 10.days.ago, covered_until: 10.days.ago, events_affected: 5
      )

      Rails.cache.clear
      stats = RailsErrorDashboard::Queries::DashboardStats.call

      expect(stats[:event_timing_incomplete]).to be_falsey
    end

    # The converse of the defect, and why liveness alone is not enough either.
    #
    # EventVolume windows occurrence rows and buckets on THEIR OWN timestamps
    # against an unwindowed group set (group_ids), so a group whose last_seen_at
    # has fallen behind its own event rows still puts events on the page. The
    # banner must not be dropped while a displayed figure is non-zero (F22), so
    # suppression requires BOTH witnesses to be silent.
    it "warns when events are displayed even though the group looks quiet" do
      app = RailsErrorDashboard::Application.find_or_create_by_name("stale-liveness-gap")
      group = RailsErrorDashboard::ErrorLog.create!(
        application_id: app.id, error_type: "StormError", message: "stale liveness",
        error_hash: SecureRandom.hex(8), occurrence_count: 10,
        occurred_at: 60.days.ago, resolved: false
      )
      # last_seen_at behind the occurrence row it should have advanced past.
      group.update_column(:last_seen_at, 40.days.ago)
      RailsErrorDashboard::ErrorOccurrence.create!(error_log_id: group.id, occurred_at: 2.hours.ago)
      RailsErrorDashboard::EventTimingGap.create!(
        application_id: app.id, covered_from: 3.hours.ago, covered_until: 2.hours.ago,
        events_affected: 5
      )

      Rails.cache.clear
      stats = RailsErrorDashboard::Queries::DashboardStats.call(application_id: app.id)

      expect(stats[:total_month]).to be > 0
      expect(stats[:event_timing_incomplete]).to be(true)
    end

    # Pre-last_seen_at rows have only occurred_at, which is why the predicate
    # keeps a separate NULL arm rather than wrapping both in COALESCE (that
    # would forfeit the index on the largest table).
    it "judges a legacy row with no last_seen_at by its occurred_at" do
      app = RailsErrorDashboard::Application.find_or_create_by_name("legacy-row-gap")
      group = RailsErrorDashboard::ErrorLog.create!(
        application_id: app.id, error_type: "StormError", message: "legacy",
        error_hash: SecureRandom.hex(8), occurrence_count: 4,
        occurred_at: 2.days.ago, resolved: false
      )
      group.update_column(:last_seen_at, nil)
      query = RailsErrorDashboard::Queries::DashboardStats.new(application_id: app.id)
      # Check the NULL arm independently: the positive monthly total below
      # would otherwise let this example pass even if that arm were removed.
      expect(query.send(:groups_seen_in_widest_window?)).to be(true)
      RailsErrorDashboard::EventTimingGap.create!(
        covered_from: 1.day.ago, covered_until: 1.day.ago, events_affected: 4
      )

      Rails.cache.clear
      stats = RailsErrorDashboard::Queries::DashboardStats.call

      expect(stats[:event_timing_incomplete]).to be(true)

      group.update_column(:occurred_at, 40.days.ago)
      expect(query.send(:groups_seen_in_widest_window?)).to be(false)
    end
  end

  context "when retention is longer than the reporting window" do
    before { RailsErrorDashboard.configuration.retention_days = 90 }

    it "still prunes a gap older than both horizons" do
      old = RailsErrorDashboard::EventTimingGap.create!(
        covered_from: 200.days.ago, covered_until: 200.days.ago, events_affected: 1
      )

      described_class.perform_now

      expect(RailsErrorDashboard::EventTimingGap.where(id: old.id)).not_to exist
    end
  end
end
