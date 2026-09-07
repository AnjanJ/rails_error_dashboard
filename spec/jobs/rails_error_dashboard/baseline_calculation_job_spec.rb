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

  it "re-raises so the queue's retry policy applies" do
    allow(RailsErrorDashboard::Services::BaselineCalculator).to receive(:calculate_all_baselines).and_raise(RuntimeError, "db gone")
    expect { described_class.perform_now }.to raise_error(RuntimeError, "db gone")
  end
end
