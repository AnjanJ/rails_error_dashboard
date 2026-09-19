# frozen_string_literal: true

require "rails_helper"

# Permanent home for the invariants the review's throwaway probes checked by
# hand (T-F5.3, carried over from the previous sprint's T6.2).
#
# Those probes were diagnostic `puts` scripts, not assertions -- they printed
# numbers for a human to eyeball and would pass whatever the numbers were.
# Promoting them verbatim would have manufactured more of exactly the defect
# F15 names: examples that are green and assert nothing. So the invariants are
# restated here as assertions, in terms of the CURRENT contract rather than the
# historical policy the probes were written against.
#
# The structural point: every defect in this sprint and the last was an
# invariant BETWEEN two readers, which no single reader's own spec can express.
# That is why they were found by review instead of by CI, twice.
RSpec.describe "EventVolume invariants", type: :model do
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
    it "sums occurrence rows, buckets and the untracked remainder to the total" do
      e = boom
      3.times { RailsErrorDashboard::Commands::LogError.call(e, user_id: 1) }

      volume = RailsErrorDashboard::Queries::EventVolume.new(
        RailsErrorDashboard::ErrorLog.unscoped, Time.current.beginning_of_day
      )
      parts = volume.send(:occurrence_events) +
              volume.send(:bucketed_events) +
              volume.send(:untracked_events)

      expect(volume.count).to eq(parts)
    end

    it "counts every captured event exactly once" do
      e = boom
      3.times { RailsErrorDashboard::Commands::LogError.call(e, user_id: 1) }

      volume = RailsErrorDashboard::Queries::EventVolume.new(
        RailsErrorDashboard::ErrorLog.unscoped, Time.current.beginning_of_day
      )

      expect(volume.count).to eq(3)
      expect(volume.count).to eq(RailsErrorDashboard::ErrorLog.sum(:occurrence_count))
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

    # The previous sprint asserted the two TOTALS agreed and stopped there,
    # which is why the breakdowns could be left unmigrated and still pass.
    it "reports the same weekly event volume in both breakdowns" do
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
