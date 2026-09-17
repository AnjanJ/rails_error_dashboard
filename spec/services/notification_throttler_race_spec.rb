# frozen_string_literal: true

require "rails_helper"

# The cooldown claim has to be atomic across CONNECTIONS, which is what
# separate processes are. A transactional example cannot show that: Rails pins
# every thread to the one connection holding the test transaction, so the
# UPDATEs would be serialised by the test harness rather than by the database.
# :non_transactional runs this group on real, committed rows (see
# spec/support/database_cleaner.rb).
RSpec.describe "NotificationThrottler.claim! under contention", :non_transactional do
  self.use_transactional_tests = false

  let(:throttler) { RailsErrorDashboard::Services::NotificationThrottler }
  let!(:row) { create(:error_log) }

  before do
    throttler.clear!
    RailsErrorDashboard.configuration.notification_cooldown_minutes = 5
  end

  after do
    throttler.clear!
    RailsErrorDashboard.reset_configuration!
  end

  it "grants exactly one of many simultaneous claims on one row" do
    start = Concurrent::CountDownLatch.new(1)

    results = Array.new(4) do
      Thread.new do
        RailsErrorDashboard::ErrorLog.connection_pool.with_connection do
          start.wait
          throttler.claim!(row)
        end
      end
    end
    start.count_down

    expect(results.map(&:value).count(true)).to eq(1)
    expect(row.reload.last_notified_at).to be_present
  end

  it "grants one claim per row when several rows are claimed at once" do
    rows = Array.new(2) { create(:error_log) }
    start = Concurrent::CountDownLatch.new(1)

    results = rows.flat_map do |r|
      Array.new(2) do
        Thread.new do
          RailsErrorDashboard::ErrorLog.connection_pool.with_connection do
            start.wait
            [ r.id, throttler.claim!(r) ]
          end
        end
      end
    end
    start.count_down

    granted = results.map(&:value).select { |(_, ok)| ok }.map(&:first)
    expect(granted.sort).to eq(rows.map(&:id).sort)
  end
end
