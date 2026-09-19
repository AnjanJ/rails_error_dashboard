# frozen_string_literal: true

require "rails_helper"

# by_hour_of_day grouped by the RAW timestamp, so N events with N distinct
# timestamps returned N intermediate rows to Ruby to produce 24 bins. Memory
# must be bounded by the reporting window, not by the number of distinct
# timestamps -- and a burst is exactly when that count explodes.
RSpec.describe RailsErrorDashboard::Queries::EventVolume, "hourly aggregation memory" do
  before do
    RailsErrorDashboard.reset_configuration!
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  let(:burst_size) { 200 }

  before do
    travel_to(Time.zone.parse("2026-09-19 10:00:00")) do
      group = RailsErrorDashboard::Commands::LogError.call(
        StandardError.new("burst boom").tap { |e|
          e.set_backtrace([ "#{Rails.root}/app/models/burst.rb:1:in 'save'" ])
        }
      )
      base = Time.current
      rows = Array.new(burst_size - 1) do |i|
        { error_log_id: group.id, occurred_at: base + ((i + 1) * 0.001),
          created_at: Time.current, updated_at: Time.current }
      end
      RailsErrorDashboard::ErrorOccurrence.insert_all(rows)
      group.update!(occurrence_count: burst_size)
    end
  end

  def volume
    described_class.new(RailsErrorDashboard::ErrorLog.unscoped, 30.days.ago)
  end

  it "returns at most one entry per hour of the day" do
    travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
      result = volume.by_hour_of_day

      expect(result.keys.size).to be <= 24
      expect(result.keys).to all(be_between(0, 23))
    end
  end

  it "counts every event in the burst" do
    travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
      expect(volume.by_hour_of_day.values.sum).to eq(burst_size)
    end
  end

  it "does not hand Ruby one row per distinct timestamp" do
    travel_to(Time.zone.parse("2026-09-19 12:00:00")) do
      grouped = volume.send(:occurrence_events_by_hour)

      # The burst spans one hour; the whole window spans 30 days. Either way
      # the row count is bounded by hours, not by the 200 distinct instants.
      expect(grouped.keys.size).to be < burst_size
    end
  end
end
