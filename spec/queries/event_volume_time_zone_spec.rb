# frozen_string_literal: true

require "rails_helper"

# "Today" must mean the operator's today.
#
# Timestamps are stored in UTC and the SQL grouped them with a bare
# DATE(column), while the Ruby side looked up Date.current in Time.zone. At
# 00:15 on the 20th in Asia/Kolkata a fresh capture is stored as 18:45 on the
# 19th UTC, so it landed on the 19th and "today" reported zero.
#
# +05:30 is deliberate: a non-whole-hour offset breaks any scheme that assumes
# day boundaries fall on a stored hour boundary.
RSpec.describe RailsErrorDashboard::Queries::EventVolume, "time zone handling" do
  before { RailsErrorDashboard.reset_configuration! }
  after  { RailsErrorDashboard.reset_configuration! }

  def boom(msg = "tz boom")
    StandardError.new(msg).tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/order.rb:1:in 'save'" ]) }
  end

  def counts_today
    described_class.by_day(RailsErrorDashboard::ErrorLog.all, 7.days.ago)
                   .fetch(Date.current, 0)
  end

  {
    "Asia/Kolkata" => "+05:30",
    "Asia/Kathmandu" => "+05:45",
    "America/Sao_Paulo" => "-03:00",
    "UTC" => "+00:00"
  }.each do |zone, offset|
    it "places a just-after-local-midnight event on today in #{zone} (#{offset})" do
      Time.use_zone(zone) do
        travel_to(Time.zone.parse("2026-09-20 00:15:00")) do
          RailsErrorDashboard::Commands::LogError.call(boom)

          expect(counts_today).to eq(1),
            "event captured at 00:15 local (#{zone}) did not land on today"
        end
      end
    end

    it "places a just-before-local-midnight event on yesterday in #{zone} (#{offset})" do
      Time.use_zone(zone) do
        travel_to(Time.zone.parse("2026-09-19 23:45:00")) do
          RailsErrorDashboard::Commands::LogError.call(boom)
        end

        travel_to(Time.zone.parse("2026-09-20 00:15:00")) do
          by_day = described_class.by_day(RailsErrorDashboard::ErrorLog.all, 7.days.ago)

          expect(by_day.fetch(Date.current - 1, 0)).to eq(1),
            "event captured at 23:45 local (#{zone}) did not land on yesterday"
          expect(by_day.fetch(Date.current, 0)).to eq(0)
        end
      end
    end
  end

  # A window spanning a DST transition cannot be bucketed with ONE current
  # offset applied to every row: the offset in force differs on either side.
  it "uses the offset in force at each row's own timestamp across a DST change" do
    Time.use_zone("America/New_York") do
      # US DST ended 2026-11-01. 2026-10-31 is EDT (-04:00); 11-02 is EST (-05:00).
      travel_to(Time.zone.parse("2026-10-31 23:30:00")) { RailsErrorDashboard::Commands::LogError.call(boom("before dst")) }
      travel_to(Time.zone.parse("2026-11-02 23:30:00")) { RailsErrorDashboard::Commands::LogError.call(boom("after dst")) }

      travel_to(Time.zone.parse("2026-11-03 12:00:00")) do
        by_day = described_class.by_day(RailsErrorDashboard::ErrorLog.all, 10.days.ago)

        expect(by_day.fetch(Date.new(2026, 10, 31), 0)).to eq(1)
        expect(by_day.fetch(Date.new(2026, 11, 2), 0)).to eq(1)
      end
    end
  end
end
