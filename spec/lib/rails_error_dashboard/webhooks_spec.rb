# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Webhooks do
  builders = %w[
    lib/rails_error_dashboard/services/webhook_payload_builder.rb
    lib/rails_error_dashboard/services/baseline_alert_payload_builder.rb
    app/jobs/rails_error_dashboard/storm_notification_job.rb
    app/jobs/rails_error_dashboard/notification_burst_summary_job.rb
  ]

  it "lists every event RED can post (webhook-v1/REQ-5, webhook-v1/REQ-6, webhook-v1/REQ-7, webhook-v1/REQ-8)" do
    expect(described_class::EVENTS.values).to contain_exactly(
      "error.created", "storm.detected", "notifications.suppressed", "baseline.anomaly_detected"
    )
  end

  it "is frozen, because it's a public contract (webhook-v1/REQ-5)" do
    expect(described_class::EVENTS).to be_frozen
  end

  builders.each do |file|
    it "leaves no event name written out in #{File.basename(file)} (webhook-v1/REQ-5, webhook-v1/REQ-6, webhook-v1/REQ-7, webhook-v1/REQ-8)" do
      code = File.readlines(RailsErrorDashboard::Engine.root.join(file)).grep_v(/\A\s*#/).join

      expect(code).not_to match(/event: "/)
    end
  end
end
