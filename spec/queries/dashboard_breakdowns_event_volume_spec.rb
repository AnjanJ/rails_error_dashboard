# frozen_string_literal: true

require "rails_helper"

# Overview's breakdowns were inventoried in the last sprint but never migrated:
# top_errors and errors_by_severity_7d still filtered GROUPS by first-seen and
# summed their LIFETIME occurrence_count. Reopening an August group in
# September produced an empty top-errors list and zero across every severity,
# while the headline total -- already on EventVolume -- counted the event.
RSpec.describe RailsErrorDashboard::Queries::DashboardStats, "weekly breakdowns after a reopen" do
  before do
    RailsErrorDashboard.reset_configuration!
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  # Same shape as the Overview/Analytics agreement fixture: the group must be
  # RESOLVED before the recurrence, so September REOPENS August's group rather
  # than opening a second one inside the window (which would hide the defect).
  before do
    group = nil
    travel_to(Time.zone.parse("2026-08-01 10:00:00")) do
      group = RailsErrorDashboard::Commands::LogError.call(
        NoMethodError.new("reopened boom").tap { |e|
          e.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ])
        }
      )
      group.update!(resolved: true, status: "resolved", resolved_at: Time.current)
    end

    travel_to(Time.zone.parse("2026-09-19 09:00:00")) do
      reopened = RailsErrorDashboard::Commands::LogError.call(
        NoMethodError.new("reopened boom").tap { |e|
          e.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ])
        }
      )
      # Fixture guard: if this stops reopening, the examples below would
      # silently stop testing what they claim to.
      expect(reopened.id).to eq(group.id)
    end
  end

  # travel_to inside each example, not an `around` -- nesting it around the
  # fixture's own travel_to raises "confusing time stubbing".
  def stats_at_noon
    travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
      Rails.cache.clear
      yield described_class.call
    end
  end

  it "lists the reopened error in the weekly top errors" do
    stats_at_noon { |stats| expect(stats[:top_errors]).to include("NoMethodError") }
  end

  it "counts the reopened event under its severity" do
    stats_at_noon { |stats| expect(stats[:errors_by_severity_7d].values.sum).to be > 0 }
  end

  it "keeps the two breakdowns in agreement" do
    stats_at_noon do |stats|
      expect(stats[:top_errors].values.sum).to eq(stats[:errors_by_severity_7d].values.sum)
    end
  end
end
