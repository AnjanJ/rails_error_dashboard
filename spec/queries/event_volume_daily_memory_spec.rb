# frozen_string_literal: true

require "rails_helper"

# by_day grouped by the RAW timestamp on SQLite, so N events with N distinct
# timestamps returned N intermediate rows to Ruby to produce ONE daily total.
# Memory must be bounded by the reporting WINDOW, not by the number of distinct
# event timestamps -- and a burst is exactly when that count explodes.
#
# The bounded key is a 15-minute truncated UTC bin: 15 minutes divides every
# UTC offset in use (including +05:30 Kolkata and +05:45 Kathmandu), so a local
# DAY boundary always falls on a bin edge. Ruby then folds the bins into local
# days using the offset in force at each bin's own instant.
RSpec.describe RailsErrorDashboard::Queries::EventVolume, "daily aggregation memory" do
  let(:burst_size) { 200 }

  around do |example|
    original_zone = Time.zone
    Time.zone = ActiveSupport::TimeZone["Asia/Kolkata"]
    example.run
  ensure
    Time.zone = original_zone
  end

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard.configuration.enable_storm_protection = false
    Rails.cache.clear
  end

  after { RailsErrorDashboard.reset_configuration! }

  def boom(msg)
    StandardError.new(msg).tap do |e|
      e.set_backtrace([ "#{Rails.root}/app/models/burst.rb:1:in 'save'" ])
    end
  end

  # The burst: 200 events with 200 DISTINCT timestamps, all inside one local
  # day. Spread over ~3.3 minutes so they also share a single 15-minute bin.
  def create_burst!(at:)
    group = nil
    travel_to(at) do
      group = RailsErrorDashboard::Commands::LogError.call(boom("daily burst"))
      base = Time.current
      rows = Array.new(burst_size - 1) do |i|
        { error_log_id: group.id, occurred_at: base + (i + 1),
          created_at: Time.current, updated_at: Time.current }
      end
      RailsErrorDashboard::ErrorOccurrence.insert_all(rows)
      group.update!(occurrence_count: burst_size)
    end
    group
  end

  def volume(from, to = nil)
    described_class.new(RailsErrorDashboard::ErrorLog.where(id: @group_ids), from, to)
  end

  describe "a burst of distinct timestamps" do
    before do
      # 10:00 IST on 2026-09-19 == 04:30 UTC. Comfortably mid-day locally.
      @group_ids = [ create_burst!(at: Time.zone.parse("2026-09-19 10:00:00")).id ]
    end

    # The row count that matters is the one SQL hands BACK, before
    # group_by_local_day folds it -- that is the allocation. Measured by
    # rebuilding the same grouped relation the query uses.
    def sql_rows_for_day_grouping(query)
      table = RailsErrorDashboard::ErrorOccurrence.table_name
      relation = query.send(
        :window,
        RailsErrorDashboard::ErrorOccurrence.where(error_log_id: query.send(:group_ids)),
        table
      )
      relation.group(query.send(:day_expression, table, "occurred_at")).count
    end

    it "does not hand Ruby one SQL row per distinct timestamp" do
      travel_to(Time.zone.parse("2026-09-19 23:00:00")) do
        rows = sql_rows_for_day_grouping(volume(30.days.ago))

        expect(rows.keys.size).to be < 20,
          "expected a bounded row count, got #{rows.keys.size} SQL rows for #{burst_size} events"
      end
    end

    it "still totals every event in the burst" do
      travel_to(Time.zone.parse("2026-09-19 23:00:00")) do
        expect(volume(30.days.ago).by_day.values.sum).to eq(burst_size)
      end
    end

    it "places the whole burst on one local day" do
      travel_to(Time.zone.parse("2026-09-19 23:00:00")) do
        by_day = volume(30.days.ago).by_day

        expect(by_day.fetch(Date.new(2026, 9, 19), 0)).to eq(burst_size)
      end
    end

    it "sums to the same number as count for the same window" do
      travel_to(Time.zone.parse("2026-09-19 23:00:00")) do
        from = 30.days.ago
        to = Time.current

        expect(volume(from, to).by_day.values.sum).to eq(volume(from, to).count)
      end
    end
  end

  describe "fractional-offset local day boundaries" do
    # 18:45 UTC on the 19th is 00:15 IST on the 20th -- the NEXT local day.
    it "places an 18:45 UTC event on the next local day in Asia/Kolkata" do
      travel_to(Time.zone.parse("2026-09-20 00:15:00")) do
        @group_ids = [ RailsErrorDashboard::Commands::LogError.call(boom("midnight edge")).id ]

        expect(Time.current.utc.strftime("%Y-%m-%d %H:%M")).to eq("2026-09-19 18:45")

        by_day = volume(7.days.ago).by_day

        expect(by_day.fetch(Date.new(2026, 9, 20), 0)).to eq(1),
          "event at 18:45 UTC must land on 2026-09-20 local (00:15 IST)"
        expect(by_day.fetch(Date.new(2026, 9, 19), 0)).to eq(0)
      end
    end

    it "places a 18:30 UTC event on the previous local day in Asia/Kolkata" do
      travel_to(Time.zone.parse("2026-09-19 23:45:00")) do
        @group_ids = [ RailsErrorDashboard::Commands::LogError.call(boom("just before midnight")).id ]

        expect(Time.current.utc.strftime("%Y-%m-%d %H:%M")).to eq("2026-09-19 18:15")

        by_day = volume(7.days.ago).by_day

        expect(by_day.fetch(Date.new(2026, 9, 19), 0)).to eq(1)
        expect(by_day.fetch(Date.new(2026, 9, 20), 0)).to eq(0)
      end
    end
  end

  # DAY_BIN_SECONDS is a literal because EventCount is autoloaded and the
  # constant is evaluated at load time. The two must not drift: the bin width
  # is what guarantees a local day boundary falls on a bin edge.
  it "bins at the same width as the storm rollup" do
    expect(described_class::DAY_BIN_SECONDS)
      .to eq(RailsErrorDashboard::EventCount::BUCKET_SECONDS)
  end

  describe "storm-shed buckets" do
    it "bounds the bucket rows and still totals them onto the local day" do
      travel_to(Time.zone.parse("2026-09-19 10:00:00")) do
        group = RailsErrorDashboard::Commands::LogError.call(boom("shed burst"))
        @group_ids = [ group.id ]
        base = RailsErrorDashboard::EventCount.bucket_for(Time.current)
        rows = Array.new(8) do |i|
          { error_log_id: group.id,
            bucket_at: base + (i * RailsErrorDashboard::EventCount::BUCKET_SECONDS),
            count: 10, created_at: Time.current, updated_at: Time.current }
        end
        RailsErrorDashboard::EventCount.insert_all(rows)
        group.update!(occurrence_count: 1 + 80)
      end

      travel_to(Time.zone.parse("2026-09-19 23:00:00")) do
        by_day = volume(30.days.ago).by_day

        expect(by_day.fetch(Date.new(2026, 9, 19), 0)).to eq(81)
      end
    end
  end
end
