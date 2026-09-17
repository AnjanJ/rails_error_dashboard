# frozen_string_literal: true

require "rails_helper"

# "Won't fix" end to end: through the real capture pipeline and through the
# storm flush, a recurrence is counted on the row and nothing else happens —
# no reopen, no notification, no new row — however old the row is.
RSpec.describe "sticky wont_fix" do
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:dispatcher) { RailsErrorDashboard::Services::ErrorNotificationDispatcher }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.async_logging = false
    config.sampling_rate = 1.0
    config.enable_storm_protection = false
    config.notification_cooldown_minutes = 0
    config.notification_threshold_alerts = [ 2, 3, 4, 10 ]
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
    allow(dispatcher).to receive(:call)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
  end

  def boom
    error = StandardError.new("sticky boom")
    error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
    error
  end

  def capture
    RailsErrorDashboard::Commands::LogError.call(boom, { controller_name: "widgets", action_name: "show" })
  end

  def mark_wont_fix(row, age: nil)
    row.update_columns(status: "wont_fix", resolved: false)
    # update!, not update_columns: the group_window bucket is derived from
    # occurred_at and has to follow it, as it would on a genuinely old row.
    row.update!(occurred_at: age.ago, last_seen_at: age.ago) if age
    row
  end

  describe "through LogError" do
    it "counts a recurrence an hour later and sends nothing" do
      row = mark_wont_fix(capture, age: 1.hour)
      expect(dispatcher).to have_received(:call).once # the first occurrence

      result = capture

      expect(result.id).to eq(row.id)
      expect(row.reload.status).to eq("wont_fix")
      expect(row.occurrence_count).to eq(2) # a threshold in this config
      expect(row.reopened_at).to be_nil
      expect(dispatcher).to have_received(:call).once
    end

    it "counts a recurrence three days later on the same row and sends nothing" do
      row = mark_wont_fix(capture, age: 3.days)

      expect { capture }.not_to change(logs, :count)

      expect(row.reload.status).to eq("wont_fix")
      expect(row.occurrence_count).to eq(2)
      expect(row.reopened_at).to be_nil
      expect(dispatcher).to have_received(:call).once
    end

    it "sends no baseline alert for a wont_fix error" do
      RailsErrorDashboard.configuration.enable_baseline_alerts = true
      RailsErrorDashboard.configuration.baseline_alert_severities = [ :critical ]
      allow_any_instance_of(logs).to receive(:baseline_anomaly).and_return({ anomaly: true, level: :critical })

      # Positive control: the same stubbed anomaly does alert while the error is open.
      row = nil
      expect { row = capture }.to have_enqueued_job(RailsErrorDashboard::BaselineAlertJob)

      mark_wont_fix(row)
      expect { capture }.not_to have_enqueued_job(RailsErrorDashboard::BaselineAlertJob)
      expect(row.reload.occurrence_count).to eq(2)
    end

    it "still reopens and notifies for a resolved error (regression pin)" do
      row = capture
      row.update_columns(status: "resolved", resolved: true, resolved_at: 1.day.ago, occurred_at: 3.days.ago)

      result = capture

      expect(result.id).to eq(row.id)
      expect(row.reload.status).to eq("new")
      expect(row.reopened_at).to be_present
      expect(dispatcher).to have_received(:call).twice
    end

    it "notifies again once the error is moved out of wont_fix" do
      row = mark_wont_fix(capture)
      row.update_columns(status: "new")

      capture # occurrence 2, a threshold

      expect(dispatcher).to have_received(:call).twice
    end
  end

  describe "through FlushStormCounts" do
    def entry(count:)
      {
        "error_class" => "StandardError", "message" => "sticky boom",
        "first_app_frame" => "#{Rails.root}/app/models/widget.rb",
        "controller_name" => "widgets", "action_name" => "show", "custom_hash" => nil,
        "count" => count, "first_seen_at" => 5.minutes.ago.iso8601, "last_seen_at" => Time.current.iso8601
      }
    end

    it "adds storm counts to a three-day-old wont_fix row without reopening it" do
      row = mark_wont_fix(capture, age: 3.days)

      expect {
        result = RailsErrorDashboard::Commands::FlushStormCounts.call(entries: [ entry(count: 40) ])
        expect(result[:success]).to be true
      }.not_to change(logs, :count)

      row.reload
      expect(row.occurrence_count).to eq(41)
      expect(row.status).to eq("wont_fix")
      expect(row.resolved).to be false
      expect(row.reopened_at).to be_nil
    end

    it "prefers the wont_fix row over a fresh unresolved sibling, as the capture path does" do
      sticky = mark_wont_fix(capture, age: 3.days)
      sibling = logs.create!(
        sticky.attributes.except("id", "group_window").merge("status" => "new", "occurred_at" => 5.minutes.ago,
                                                             "last_seen_at" => 5.minutes.ago, "occurrence_count" => 1)
      )

      RailsErrorDashboard::Commands::FlushStormCounts.call(entries: [ entry(count: 7) ])

      expect(sticky.reload.occurrence_count).to eq(8)
      expect(sibling.reload.occurrence_count).to eq(1)
    end

    it "still reopens a resolved row (regression pin)" do
      row = capture
      row.update_columns(status: "resolved", resolved: true, resolved_at: 1.day.ago, occurred_at: 3.days.ago)

      RailsErrorDashboard::Commands::FlushStormCounts.call(entries: [ entry(count: 5) ])

      expect(row.reload.status).to eq("new")
      expect(row.occurrence_count).to eq(6)
    end
  end
end
