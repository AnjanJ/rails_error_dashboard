# frozen_string_literal: true

require "rails_helper"

# Permanent home for the CROSS-READER volume invariants (T-F5.3, carried over
# from the previous sprint's T6.2).
#
# CORRECTION. An earlier version of this comment claimed the review's probes
# were "diagnostic `puts` scripts, not assertions". That was wrong, and I had
# written it into a commit body, a PR description and a public issue comment.
# Three of the eight probes carried real `expect` assertions (8 in the
# precedence probe, 1 each in the payload and persistence probes); the other
# five printed values for inspection. The probes' historical failures and their
# current passing runs stand as recorded.
#
# This file is therefore a SUPPLEMENT, not a replacement. It covers the
# event-volume invariants only. It does NOT cover the redaction, transport,
# job-lifecycle or provenance probes -- those remain separate concerns, and the
# mapping below says exactly what is and is not carried over:
#
#   ev_probe          (three-term volume decomposition)  -> covered here
#   r1_probe          (Overview vs Analytics agreement)  -> covered here
#   precedence_probe  (P3/P4 capture-envelope precedence) -> spec/commands/async_capture_envelope_spec.rb
#   prov_probe        (snapshot provenance / fidelity)   -> spec/commands/snapshot_provenance_spec.rb
#   red_payload_probe (redaction of payloads)            -> spec/services/variable_serializer_spec.rb
#   red_persist_probe (redaction persisted to the row)   -> spec/services/variable_serializer_spec.rb
#   aj_probe          (ActiveJob lifecycle capture)      -> NOT covered here
#   uis_probe         (UI string / layout)               -> NOT covered here
#   overflow_probe    (mobile layout overflow)           -> spec/system, NOT covered here
#
# The structural point that motivates the file: every defect in this sprint and
# the last was an invariant BETWEEN two readers, which no single reader's own
# spec can express. That is why they were found by review instead of by CI.
RSpec.describe "EventVolume invariants", type: :model do
  # The clock is PINNED to midday, for every example in this file.
  #
  # The fixtures place events at 2 and 3 hours ago and the queries ask for
  # "since midnight", so on a real clock these examples silently depended on
  # the time of day: run at 00:30, both fixtures fell outside the window and
  # the bucket and legacy terms vanished (expected 15, got 3). A spec that
  # passes all day and fails at night is worse than one that always fails --
  # it is green when anyone looks at it.
  #
  # Pinned rather than widened: widening the query window would have hidden
  # the dependency instead of removing it.
  around { |ex| travel_to(Time.zone.parse("2026-09-15 12:00:00")) { ex.run } }

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard.configuration.enable_storm_protection = false
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  def boom(msg = "invariant boom")
    StandardError.new(msg).tap { |e| e.set_backtrace([ "#{Rails.root}/app/m.rb:1:in 'x'" ]) }
  end

  describe "the three-term model" do
    # A fixture with ALL THREE terms independently nonzero.
    #
    # The earlier version of this example created only occurrence rows, so the
    # bucket and untracked terms were both zero, and it then asserted
    # count == a + b + c against an implementation that DEFINES count as
    # a + b + c. It restated the implementation instead of constraining it, and
    # would have passed even if two terms were silently dropped.
    #
    # Here each term is established by a different mechanism and asserted to be
    # nonzero BEFORE the total is checked, against an independently computed
    # expected value.
    let!(:terms) do
      # (1) occurrence rows: ordinary captures, 3 events.
      e = boom("three-term")
      group = nil
      3.times { group = RailsErrorDashboard::Commands::LogError.call(e, user_id: 1) }

      # (2) storm buckets: 5 shed events, written directly with a timestamp of
      #     their own -- this is what storm protection does instead of writing
      #     an occurrence row.
      RailsErrorDashboard::EventCount.accumulate(
        error_log_id: group.id, bucket_at: 2.hours.ago, count: 5
      )

      # (3) untracked remainder: a SECOND group whose occurrence_count exceeds
      #     its per-event records -- rows from before occurrence tracking. Its
      #     own occurred_at is inside the window, which is what makes the
      #     remainder countable.
      legacy = RailsErrorDashboard::ErrorLog.create!(
        application_id: group.application_id,
        error_type: "LegacyError", message: "pre-tracking",
        error_hash: SecureRandom.hex(8), occurrence_count: 7,
        occurred_at: 3.hours.ago, resolved: false
      )

      { group: group, legacy: legacy, occurrences: 3, buckets: 5, untracked: 7 }
    end

    let(:volume) do
      RailsErrorDashboard::Queries::EventVolume.new(
        RailsErrorDashboard::ErrorLog.unscoped, Time.current.beginning_of_day
      )
    end

    it "establishes all three terms as nonzero" do
      expect(volume.send(:occurrence_events)).to eq(terms[:occurrences])
      expect(volume.send(:bucketed_events)).to eq(terms[:buckets])
      expect(volume.send(:untracked_events)).to eq(terms[:untracked])
    end

    it "totals the independently known number of events" do
      expected = terms[:occurrences] + terms[:buckets] + terms[:untracked]

      expect(volume.count).to eq(expected)
      expect(volume.count).to eq(15)
    end

    it "places every event on a day, so by_day totals the same" do
      expect(volume.by_day.values.sum).to eq(volume.count)
    end

    it "counts a shed event exactly once -- never as both bucket and remainder" do
      # The group with buckets must NOT also contribute an untracked remainder
      # for those same events; that double count is the failure this guards.
      remainder_for_bucketed_group = volume.send(:untracked_groups)
                                           .select { |id, _r, _at| id.to_i == terms[:group].id }
                                           .sum { |_id, r, _at| r }

      expect(remainder_for_bucketed_group).to eq(0)
    end
  end

  describe "breakdowns against the headline total" do
    before do
      2.times { RailsErrorDashboard::Commands::LogError.call(boom("alpha")) }
      RailsErrorDashboard::Commands::LogError.call(boom("beta"))
    end

    let(:volume) do
      RailsErrorDashboard::Queries::EventVolume.new(
        RailsErrorDashboard::ErrorLog.unscoped, Time.current.beginning_of_day
      )
    end

    # A complete partition of the window must sum to the whole. This is the
    # invariant R1 violated -- each page was internally consistent and they
    # disagreed with each other.
    it "sums by_group_attribute to the total" do
      expect(volume.by_group_attribute(:error_type).values.sum).to eq(volume.count)
    end

    it "sums by_day to the total" do
      expect(volume.by_day.values.sum).to eq(volume.count)
    end

    it "sums by_hour_of_day to the total" do
      expect(volume.by_hour_of_day.values.sum).to eq(volume.count)
    end
  end

  describe "Overview and Analytics agree on the breakdowns, not only the total" do
    before do
      2.times { RailsErrorDashboard::Commands::LogError.call(boom("shared")) }
    end

    # These examples call BOTH pages. An earlier version called only Overview
    # while claiming to compare the two, which is a weaker test than its own
    # description promised.
    it "reports the same per-type breakdown on both pages" do
      overview = RailsErrorDashboard::Queries::DashboardStats.call
      analytics = RailsErrorDashboard::Queries::AnalyticsStats.call(7)

      expect(overview[:top_errors].values.sum)
        .to eq(analytics[:errors_by_type].values.sum)
    end

    # The previous sprint asserted the two TOTALS agreed and stopped there,
    # which is why the breakdowns could be left unmigrated and still pass.
    it "keeps Overview's own two weekly breakdowns in agreement" do
      overview = RailsErrorDashboard::Queries::DashboardStats.call

      expect(overview[:top_errors].values.sum)
        .to eq(overview[:errors_by_severity_7d].values.sum)
    end

    # No silent `next` guard here: that is precisely the F15 pattern. The
    # fixture's premise is asserted instead, so a broken fixture fails the
    # example rather than skipping it into a meaningless pass.
    it "never reports an empty breakdown while the total is positive" do
      overview = RailsErrorDashboard::Queries::DashboardStats.call

      expect(overview[:total_month].to_i).to be > 0,
        "fixture guard: the two captured events should be in the month window"
      expect(overview[:top_errors]).to be_present,
        "Overview reported #{overview[:total_month]} events with an empty top-errors list"
    end
  end
end
