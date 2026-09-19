# frozen_string_literal: true

require "rails_helper"

# The two pages must answer the same question with the same number.
#
# R1 was not caught by either page's own specs, because each page was
# internally consistent and they disagreed with EACH OTHER: Overview said one
# event today while Analytics said zero for a thirty-day window that contained
# it -- and Analytics' own affected-users table listed that very event.
#
# No existing spec compared them. That is the structural gap this file closes:
# an invariant between two readers cannot be expressed inside either one.
RSpec.describe "Overview and Analytics agree on event volume" do
  before do
    RailsErrorDashboard.reset_configuration!
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  def overview_total_for(days)
    RailsErrorDashboard::Queries::DashboardStats.call
      .fetch(days == 1 ? :total_today : :total_month)
  end

  def analytics_total_for(days)
    RailsErrorDashboard::Queries::AnalyticsStats.call(days)
      .dig(:error_stats, :total)
  end

  # The reviewer's R1 reproduction: a group born outside the window, with a
  # recurrence inside it. Analytics filtered the GROUP out by its first-seen
  # date and therefore never counted the event.
  context "when an old group recurs inside the window" do
    # The group must be RESOLVED before the recurrence, so that September's
    # capture REOPENS the August group rather than opening a new one. Without
    # that, two separate groups exist, the second is born inside the window,
    # and Analytics' first-seen filter happens to include it -- the defect
    # hides and the test passes for the wrong reason. (It did, on the first
    # draft of this spec.)
    before do
      group = nil
      travel_to(Time.zone.parse("2026-08-01 10:00:00")) do
        group = RailsErrorDashboard::Commands::LogError.call(
          StandardError.new("agreement boom").tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ]) },
          user_id: 10
        )
        group.update!(resolved: true, status: "resolved", resolved_at: Time.current)
      end

      travel_to(Time.zone.parse("2026-09-19 10:00:00")) do
        reopened = RailsErrorDashboard::Commands::LogError.call(
          StandardError.new("agreement boom").tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ]) },
          user_id: 20
        )
        # Guard the fixture itself: if this ever stops reopening, the examples
        # below would silently stop testing what they claim to.
        expect(reopened.id).to eq(group.id)
      end
    end

    it "reports the same 30-day total on both pages" do
      travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
        Rails.cache.clear
        expect(analytics_total_for(30)).to eq(overview_total_for(30))
      end
    end

    it "does not report zero while its own user table lists the event" do
      travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
        Rails.cache.clear
        result = RailsErrorDashboard::Queries::AnalyticsStats.call(30)
        # fetch, not []: this example read :user_impact / :affected_users --
        # keys AnalyticsStats has never returned -- so `next if users.blank?`
        # fired every run and the example exited before asserting anything. A
        # green test that tests nothing is worse than no test.
        users = result.fetch(:top_users)

        expect(users).to be_present,
          "fixture guard: the reopened group should appear in the user table"
        expect(result.dig(:error_stats, :total)).to be > 0,
          "Analytics reported 0 events while listing #{users.inspect} in its user table"
      end
    end
  end

  # An exhaustive breakdown partitions every event exactly once, so its sum
  # must EQUAL the headline total. `<=` would let an empty breakdown pass,
  # which is the failure mode being guarded against.
  context "internal consistency of Analytics' own figures" do
    before do
      travel_to(Time.zone.parse("2026-09-18 09:00:00")) do
        3.times do |i|
          RailsErrorDashboard::Commands::LogError.call(
            StandardError.new("consistency boom #{i}").tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/order.rb:#{i}:in 'save'" ]) },
            user_id: i
          )
        end
      end
    end

    it "sums by_type to exactly the headline total" do
      travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
        Rails.cache.clear
        stats = RailsErrorDashboard::Queries::AnalyticsStats.call(30)
                                                            .fetch(:error_stats)

        expect(stats[:by_type].values.sum).to eq(stats[:total])
      end
    end

    it "sums by_day to exactly the headline total" do
      travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
        Rails.cache.clear
        stats = RailsErrorDashboard::Queries::AnalyticsStats.call(30)
                                                            .fetch(:error_stats)

        expect(stats[:by_day].values.sum).to eq(stats[:total])
      end
    end
  end
end
