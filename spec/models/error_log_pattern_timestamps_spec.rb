# frozen_string_literal: true

require "rails_helper"

# Pattern Insights read ErrorLog.occurred_at: one timestamp per grouped row,
# however many times the error had happened. The rhythm it looks for lives in
# the per-event occurrence rows.
RSpec.describe RailsErrorDashboard::ErrorLog, "pattern timestamps" do
  let(:error) { create(:error_log, error_type: "TimeoutError", platform: "API", occurred_at: 1.day.ago) }

  before { RailsErrorDashboard.configuration.enable_occurrence_patterns = true }
  after { RailsErrorDashboard.reset_configuration! }

  def occurrence_at(time, error_log = error)
    RailsErrorDashboard::ErrorOccurrence.create!(error_log: error_log, occurred_at: time)
  end

  it "analyses one timestamp per occurrence, oldest first" do
    times = [ 3.days.ago.change(hour: 9), 2.days.ago.change(hour: 9), 1.day.ago.change(hour: 9) ]
    times.shuffle.each { |t| occurrence_at(t) }

    stamps = error.send(:pattern_timestamps, days: 30)

    expect(stamps.size).to eq(3)
    expect(stamps).to eq(stamps.sort)
    expect(error.occurrence_pattern(days: 30)[:total_errors]).to eq(3)
  end

  it "includes occurrences of the same error type and platform on other rows" do
    sibling = create(:error_log, error_type: "TimeoutError", platform: "API", occurred_at: 2.days.ago)
    occurrence_at(1.day.ago)
    occurrence_at(2.days.ago, sibling)

    expect(error.send(:pattern_timestamps, days: 30).size).to eq(2)
  end

  it "ignores occurrences outside the window and of other errors" do
    occurrence_at(40.days.ago)
    occurrence_at(1.day.ago, create(:error_log, error_type: "OtherError", platform: "API"))
    occurrence_at(1.day.ago)

    expect(error.send(:pattern_timestamps, days: 30).size).to eq(1)
  end

  it "falls back to the grouped rows when no occurrence rows exist" do
    create(:error_log, error_type: "TimeoutError", platform: "API", occurred_at: 2.days.ago)

    expect(error.send(:pattern_timestamps, days: 30).size).to eq(2)
  end

  it "caps the sample at PATTERN_SAMPLE_LIMIT most recent occurrences" do
    stub_const("RailsErrorDashboard::ErrorLog::PATTERN_SAMPLE_LIMIT", 2)
    occurrence_at(3.days.ago)
    occurrence_at(2.days.ago)
    newest = occurrence_at(1.day.ago)

    stamps = error.send(:pattern_timestamps, days: 30)

    expect(stamps.size).to eq(2)
    expect(stamps.last).to be_within(1.second).of(newest.occurred_at)
  end
end
