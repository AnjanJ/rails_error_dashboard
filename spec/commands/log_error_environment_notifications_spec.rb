# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::LogError, "environment notification allowlist" do
  let(:dispatcher) { RailsErrorDashboard::Services::ErrorNotificationDispatcher }

  before do
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard.configuration.enable_storm_protection = false
    RailsErrorDashboard::Services::NotificationThrottler.clear!
  end

  after do
    RailsErrorDashboard::Services::NotificationThrottler.clear!
    RailsErrorDashboard.reset_configuration!
  end

  def boom(message = "notify boom")
    error = RuntimeError.new(message)
    error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
    error
  end

  it "dispatches for a new error when no allowlist is set" do
    expect(dispatcher).to receive(:call).once
    described_class.call(boom)
  end

  it "does not dispatch for a new error outside the allowlist" do
    RailsErrorDashboard.configuration.notification_environments = %w[production]
    RailsErrorDashboard.configuration.environment = "staging"
    expect(dispatcher).not_to receive(:call)
    described_class.call(boom)
  end

  it "dispatches when the error's environment is listed" do
    RailsErrorDashboard.configuration.notification_environments = %w[production]
    RailsErrorDashboard.configuration.environment = "production"
    expect(dispatcher).to receive(:call).once
    described_class.call(boom)
  end

  it "suppresses the reopen notification outside the allowlist" do
    RailsErrorDashboard.configuration.environment = "production"
    allow(dispatcher).to receive(:call)
    log = described_class.call(boom("reopen me"))
    log.update!(resolved: true, status: "resolved", resolved_at: 1.hour.ago)

    RailsErrorDashboard.configuration.notification_environments = %w[uat]
    expect(dispatcher).not_to receive(:call)
    reopened = described_class.call(boom("reopen me"))
    expect(reopened.id).to eq(log.id)
    expect(reopened.resolved).to be(false)
  end

  describe "baseline alerts" do
    before do
      RailsErrorDashboard.configuration.enable_baseline_alerts = true
      RailsErrorDashboard.configuration.baseline_alert_severities = %i[critical high medium low]
      allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:baseline_anomaly)
        .and_return({ anomaly: true, level: :critical, std_devs_above: 3.2 })
      allow(dispatcher).to receive(:call)
    end

    it "enqueues when no allowlist is set" do
      expect { described_class.call(boom) }
        .to have_enqueued_job(RailsErrorDashboard::BaselineAlertJob)
    end

    it "does not enqueue outside the allowlist" do
      RailsErrorDashboard.configuration.notification_environments = %w[production]
      RailsErrorDashboard.configuration.environment = "staging"
      expect { described_class.call(boom) }
        .not_to have_enqueued_job(RailsErrorDashboard::BaselineAlertJob)
    end
  end
end
