# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::BaselineCalculationJob, type: :job do
  it "recalculates every baseline and returns the calculator's summary" do
    log = create(:error_log, error_type: "NoMethodError", platform: "API", occurred_at: 1.day.ago)
    create(:error_occurrence, error_log: log, occurred_at: 1.day.ago)

    result = described_class.perform_now

    expect(result[:calculated]).to be > 0
    expect(RailsErrorDashboard::ErrorBaseline.where(error_type: "NoMethodError", platform: "API").count).to be > 0
  end

  # Two layers: #perform is where the failure is raised, perform_now is where
  # ApplicationJob's retry_on catches it and schedules another attempt. This
  # used to be one assertion on perform_now, which passed only because
  # retry_on was shadowed by a rescue_from that re-raised past it -- so "the
  # queue's retry policy" never actually ran. Pin both layers so a shadowed
  # retry handler fails the suite instead of going unnoticed.
  it "raises out of #perform so the failure is not silently swallowed" do
    allow(RailsErrorDashboard::Services::BaselineCalculator).to receive(:calculate_all_baselines).and_raise(RuntimeError, "db gone")
    expect { described_class.new.perform }.to raise_error(RuntimeError, "db gone")
  end

  it "schedules a retry rather than reporting success" do
    allow(RailsErrorDashboard::Services::BaselineCalculator).to receive(:calculate_all_baselines).and_raise(RuntimeError, "db gone")

    expect {
      described_class.perform_now
    }.to change { described_class.queue_adapter.enqueued_jobs.count { |j| j[:job] == described_class } }.by(1)
  end
end
