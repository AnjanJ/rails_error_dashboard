# frozen_string_literal: true

require "rails_helper"

# The docs promised hourly cascade detection by a background job; no job ran
# the detector, so the Cascades card stayed empty on every install.
RSpec.describe RailsErrorDashboard::CascadeDetectionJob, type: :job do
  after { RailsErrorDashboard.reset_configuration! }

  it "runs the detector over the given window when cascades are enabled" do
    RailsErrorDashboard.configuration.enable_error_cascades = true
    allow(RailsErrorDashboard::Services::CascadeDetector).to receive(:call).and_return({ detected: 2, updated: 1 })

    result = described_class.perform_now(lookback_hours: 6)

    expect(RailsErrorDashboard::Services::CascadeDetector).to have_received(:call).with(lookback_hours: 6)
    expect(result).to eq({ detected: 2, updated: 1 })
  end

  it "defaults to a one-hour window, matching an hourly schedule" do
    RailsErrorDashboard.configuration.enable_error_cascades = true
    allow(RailsErrorDashboard::Services::CascadeDetector).to receive(:call).and_return({ detected: 0, updated: 0 })

    described_class.perform_now

    expect(RailsErrorDashboard::Services::CascadeDetector).to have_received(:call).with(lookback_hours: 1)
  end

  it "does nothing when enable_error_cascades is off" do
    RailsErrorDashboard.configuration.enable_error_cascades = false
    allow(RailsErrorDashboard::Services::CascadeDetector).to receive(:call)

    result = described_class.perform_now

    expect(RailsErrorDashboard::Services::CascadeDetector).not_to have_received(:call)
    expect(result[:skipped]).to be_present
  end

  it "detects a real cascade end to end" do
    RailsErrorDashboard.configuration.enable_error_cascades = true
    parent = create(:error_log, error_type: "Redis::ConnectionError")
    child = create(:error_log, error_type: "CacheMissError")
    5.times do |i|
      at = (50 - i * 10).minutes.ago
      RailsErrorDashboard::ErrorOccurrence.create!(error_log: parent, occurred_at: at)
      RailsErrorDashboard::ErrorOccurrence.create!(error_log: child, occurred_at: at + 20.seconds)
    end

    result = described_class.perform_now(lookback_hours: 2)

    expect(result[:detected]).to be >= 1
    expect(RailsErrorDashboard::CascadePattern.where(parent_error_id: parent.id, child_error_id: child.id)).to exist
  end
end
