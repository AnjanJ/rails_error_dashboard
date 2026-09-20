# frozen_string_literal: true

require "rails_helper"
require "zlib"

# by_hour_of_day must report the hour on the OPERATOR's clock.
#
# On SQLite the grouping key is produced in SQL as a UTC-hour-truncated
# STRING, and Ruby then converted it with Time.zone.parse -- which reads a
# bare string as LOCAL time, so the UTC hour was reported verbatim. Worse,
# truncating to the UTC hour destroys the sub-hour boundary that fractional
# zones need: in Asia/Kolkata (+05:30) events at 00:15 and 00:45 UTC belong to
# different local hours but share a UTC hour.
#
# Fixing the parse alone cannot fix the second defect -- the bins themselves
# have to preserve local-hour boundaries.
RSpec.describe RailsErrorDashboard::Queries::EventVolume, "hourly zone handling" do
  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard.configuration.enable_storm_protection = false
  end

  after { RailsErrorDashboard.reset_configuration! }

  around do |example|
    original = Time.zone
    example.run
  ensure
    Time.zone = original
  end

  # A distinct backtrace per message: grouping fingerprints the backtrace, so
  # a shared one collapses every capture into ONE group (keeping the first
  # message) and `where(message: ...)` would then miss rows.
  def boom(msg)
    line = Zlib.crc32(msg) % 10_000
    StandardError.new(msg).tap { |e| e.set_backtrace([ "#{Rails.root}/app/models/order.rb:#{line}:in 'save'" ]) }
  end

  # Capture at an exact UTC instant, whatever Time.zone currently is.
  def capture_at_utc(utc_string, msg)
    travel_to(Time.find_zone("UTC").parse(utc_string)) do
      RailsErrorDashboard::Commands::LogError.call(boom(msg))
    end
  end

  # Only the rows this example created: an ErrorLog scope narrowed to the
  # groups whose message we control.
  def hours_for(messages)
    scope = RailsErrorDashboard::ErrorLog.where(message: messages)
    described_class.new(scope, Time.find_zone("UTC").parse("2026-09-01 00:00:00")).by_hour_of_day
  end

  it "reports an event at 10:15 UTC as hour 6 in America/New_York" do
    Time.zone = ActiveSupport::TimeZone["America/New_York"]
    capture_at_utc("2026-09-19 10:15:00", "ny boom")

    result = hours_for([ "ny boom" ])

    expect(result.reject { |_h, n| n.zero? }).to eq(6 => 1)
  end

  it "splits 00:15 and 00:45 UTC into local hours 5 and 6 in Asia/Kolkata" do
    Time.zone = ActiveSupport::TimeZone["Asia/Kolkata"]
    capture_at_utc("2026-09-19 00:15:00", "kolkata early")
    capture_at_utc("2026-09-19 00:45:00", "kolkata late")

    result = hours_for([ "kolkata early", "kolkata late" ])

    expect(result.reject { |_h, n| n.zero? }).to eq(5 => 1, 6 => 1)
  end

  it "splits across a +05:45 local hour boundary in Asia/Kathmandu" do
    Time.zone = ActiveSupport::TimeZone["Asia/Kathmandu"]
    # 00:10 UTC -> 05:55 local (hour 5); 00:20 UTC -> 06:05 local (hour 6).
    capture_at_utc("2026-09-19 00:10:00", "kathmandu early")
    capture_at_utc("2026-09-19 00:20:00", "kathmandu late")

    result = hours_for([ "kathmandu early", "kathmandu late" ])

    expect(result.reject { |_h, n| n.zero? }).to eq(5 => 1, 6 => 1)
  end

  it "stays bounded to 24 keys and sums to the events it was given" do
    Time.zone = ActiveSupport::TimeZone["Asia/Kolkata"]
    messages = []
    6.times do |i|
      msg = "bounded #{i}"
      messages << msg
      capture_at_utc(format("2026-09-19 %02d:%02d:00", i * 3, i * 7), msg)
    end

    result = hours_for(messages)

    expect(result.keys.size).to be <= 24
    expect(result.keys).to all(be_between(0, 23))
    expect(result.values.sum).to eq(6)
  end

  it "keeps the grouped row count bounded by the window, not by distinct timestamps" do
    Time.zone = ActiveSupport::TimeZone["Asia/Kolkata"]
    burst = 200

    travel_to(Time.find_zone("UTC").parse("2026-09-19 10:00:00")) do
      group = RailsErrorDashboard::Commands::LogError.call(boom("hourly zone burst"))
      base = Time.current
      rows = Array.new(burst - 1) do |i|
        { error_log_id: group.id, occurred_at: base + ((i + 1) * 0.001),
          created_at: Time.current, updated_at: Time.current }
      end
      RailsErrorDashboard::ErrorOccurrence.insert_all(rows)
      group.update!(occurrence_count: burst)
    end

    scope = RailsErrorDashboard::ErrorLog.where(message: "hourly zone burst")
    volume = described_class.new(scope, Time.find_zone("UTC").parse("2026-09-01 00:00:00"))

    grouped = volume.send(:occurrence_events_by_hour)

    expect(grouped.keys.size).to be < 20
    expect(volume.by_hour_of_day.values.sum).to eq(burst)
  end
end
