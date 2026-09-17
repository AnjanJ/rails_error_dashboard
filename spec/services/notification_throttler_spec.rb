# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::NotificationThrottler do
  let(:error_log) do
    instance_double(
      RailsErrorDashboard::ErrorLog,
      error_hash: "abc123def456",
      error_type: "NoMethodError",
      occurrence_count: 1
    )
  end

  before do
    described_class.clear!
    RailsErrorDashboard.configuration.notification_minimum_severity = :low
    RailsErrorDashboard.configuration.notification_cooldown_minutes = 5
    RailsErrorDashboard.configuration.notification_threshold_alerts = [ 10, 50, 100, 500, 1000 ]
  end

  after do
    described_class.clear!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".should_notify?" do
    before do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)
    end

    it "returns true when no cooldown is active" do
      expect(described_class.should_notify?(error_log)).to be true
    end

    it "returns false when same error_hash was notified within cooldown" do
      described_class.record_notification(error_log)
      expect(described_class.should_notify?(error_log)).to be false
    end

    it "returns true after cooldown expires" do
      described_class.record_notification(error_log)

      travel_to(6.minutes.from_now) do
        expect(described_class.should_notify?(error_log)).to be true
      end
    end

    it "returns true when cooldown is set to 0 (disabled)" do
      RailsErrorDashboard.configuration.notification_cooldown_minutes = 0
      described_class.record_notification(error_log)
      expect(described_class.should_notify?(error_log)).to be true
    end

    it "returns false when severity is below minimum" do
      RailsErrorDashboard.configuration.notification_minimum_severity = :critical
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)

      expect(described_class.should_notify?(error_log)).to be false
    end

    it "returns true when severity meets minimum" do
      RailsErrorDashboard.configuration.notification_minimum_severity = :high
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)

      expect(described_class.should_notify?(error_log)).to be true
    end

    it "returns true when severity exceeds minimum" do
      RailsErrorDashboard.configuration.notification_minimum_severity = :medium
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:critical)

      expect(described_class.should_notify?(error_log)).to be true
    end
  end

  describe ".severity_meets_minimum?" do
    it "returns true when minimum is :low (default, notify all)" do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:low)

      expect(described_class.severity_meets_minimum?(error_log)).to be true
    end

    it "with :critical minimum only allows critical errors" do
      RailsErrorDashboard.configuration.notification_minimum_severity = :critical

      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)
      expect(described_class.severity_meets_minimum?(error_log)).to be false

      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:critical)
      expect(described_class.severity_meets_minimum?(error_log)).to be true
    end

    it "with :high minimum allows critical and high" do
      RailsErrorDashboard.configuration.notification_minimum_severity = :high

      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:medium)
      expect(described_class.severity_meets_minimum?(error_log)).to be false

      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)
      expect(described_class.severity_meets_minimum?(error_log)).to be true

      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:critical)
      expect(described_class.severity_meets_minimum?(error_log)).to be true
    end
  end

  describe ".threshold_reached?" do
    it "returns true when occurrence_count matches a threshold" do
      [ 10, 50, 100, 500, 1000 ].each do |count|
        log = instance_double(RailsErrorDashboard::ErrorLog, occurrence_count: count)
        expect(described_class.threshold_reached?(log)).to be true
      end
    end

    it "returns false for non-milestone counts" do
      [ 1, 2, 5, 11, 49, 99, 101, 999 ].each do |count|
        log = instance_double(RailsErrorDashboard::ErrorLog, occurrence_count: count)
        expect(described_class.threshold_reached?(log)).to be false
      end
    end

    it "returns false when threshold alerts are disabled (empty array)" do
      RailsErrorDashboard.configuration.notification_threshold_alerts = []
      log = instance_double(RailsErrorDashboard::ErrorLog, occurrence_count: 100)
      expect(described_class.threshold_reached?(log)).to be false
    end

    it "respects custom threshold values" do
      RailsErrorDashboard.configuration.notification_threshold_alerts = [ 5, 25 ]
      expect(described_class.threshold_reached?(
        instance_double(RailsErrorDashboard::ErrorLog, occurrence_count: 5)
      )).to be true
      expect(described_class.threshold_reached?(
        instance_double(RailsErrorDashboard::ErrorLog, occurrence_count: 10)
      )).to be false
    end
  end

  describe ".record_notification" do
    it "records timestamp for cooldown tracking" do
      freeze_time do
        described_class.record_notification(error_log)
        # Should now be in cooldown
        expect(described_class.should_notify?(error_log)).to be false
      end
    end
  end

  describe ".clear!" do
    it "resets all cooldown state" do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)

      described_class.record_notification(error_log)
      expect(described_class.should_notify?(error_log)).to be false

      described_class.clear!
      expect(described_class.should_notify?(error_log)).to be true
    end
  end

  # The cooldown used to live only in a per-process Hash: every Puma worker and
  # every job process notified independently, and a restart forgot it. claim!
  # takes it in the database, where exactly one process can win.
  describe ".claim!" do
    let(:row) { create(:error_log) }

    before { RailsErrorDashboard.configuration.notification_cooldown_minutes = 5 }

    # "Another process" = the same row, but none of this process's memory.
    def as_another_process
      described_class.clear!
      yield
    end

    it "grants the first claim and stamps the row" do
      freeze_time do
        expect(described_class.claim!(row)).to be true
        expect(row.reload.last_notified_at).to eq(Time.current)
      end
    end

    it "refuses a second claim inside the cooldown, even from another process" do
      expect(described_class.claim!(row)).to be true

      as_another_process { expect(described_class.claim!(row)).to be false }
    end

    it "does not move the stamp when a claim is refused" do
      described_class.claim!(row)
      stamped = row.reload.last_notified_at

      travel_to(2.minutes.from_now) { described_class.claim!(row) }

      expect(row.reload.last_notified_at).to eq(stamped)
    end

    it "grants a claim again once the cooldown has passed" do
      described_class.claim!(row)

      travel_to(6.minutes.from_now) do
        as_another_process { expect(described_class.claim!(row)).to be true }
      end
    end

    it "always grants, and still stamps, when the cooldown is disabled" do
      RailsErrorDashboard.configuration.notification_cooldown_minutes = 0

      expect(described_class.claim!(row)).to be true
      expect(described_class.claim!(row)).to be true
      expect(row.reload.last_notified_at).to be_present
    end

    it "always grants, and still stamps, when asked not to respect the cooldown" do
      described_class.claim!(row)

      travel_to(1.minute.from_now) do
        expect(described_class.claim!(row, respect_cooldown: false)).to be true
        expect(row.reload.last_notified_at).to eq(Time.current)
      end
    end

    it "keeps separate cooldowns for separate rows" do
      other = create(:error_log)
      described_class.claim!(row)

      expect(described_class.claim!(other)).to be true
    end

    it "issues exactly one UPDATE and no SELECT" do
      statements = []
      counter = ->(_n, _s, _f, _i, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
      row # create outside the subscription

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.claim!(row) }

      expect(statements.grep(/\A\s*UPDATE/i).size).to eq(1)
      expect(statements.grep(/\A\s*SELECT/i)).to be_empty
    end

    context "when the last_notified_at column is absent (migration not run yet)" do
      before do
        allow(RailsErrorDashboard::ErrorLog).to receive(:column_names)
          .and_return(RailsErrorDashboard::ErrorLog.column_names - [ "last_notified_at" ])
      end

      it "falls back to the in-process cooldown without touching the column" do
        expect(described_class.claim!(row)).to be true
        expect(described_class.claim!(row)).to be false
        expect(row.reload.last_notified_at).to be_nil
      end

      it "grants again after the cooldown" do
        described_class.claim!(row)

        travel_to(6.minutes.from_now) { expect(described_class.claim!(row)).to be true }
      end
    end

    it "fails open: a database error means notify" do
      allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_raise(ActiveRecord::StatementInvalid, "db down")

      expect(described_class.claim!(row)).to be true
    end

    it "fails open for nil" do
      expect(described_class.claim!(nil)).to be true
    end
  end

  # The fallback Hash had no bound and cleanup! had no callers, so a process
  # that saw a million distinct errors kept a million timestamps.
  describe "in-process fallback bounds" do
    def fake_log(i)
      instance_double(RailsErrorDashboard::ErrorLog, error_hash: "hash_#{i}", error_type: "NoMethodError")
    end

    def tracked
      described_class.instance_variable_get(:@last_notification_times)
    end

    it "never holds more than MAX_TRACKED keys" do
      5_000.times { |i| described_class.record_notification(fake_log(i)) }

      expect(tracked.size).to be <= described_class::MAX_TRACKED
      expect(described_class::MAX_TRACKED).to eq(1_000)
    end

    it "evicts the oldest entries first, keeping the most recent cooldowns" do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify).and_return(:high)
      1_500.times { |i| described_class.record_notification(fake_log(i)) }

      expect(described_class.should_notify?(fake_log(1_499))).to be false # still in cooldown
      expect(described_class.should_notify?(fake_log(0))).to be true      # evicted
    end

    it "sweeps expired entries on insert" do
      travel_to(10.minutes.ago) { 50.times { |i| described_class.record_notification(fake_log(i)) } }

      described_class.record_notification(fake_log(9_999))

      expect(tracked.keys).to eq([ "hash_9999" ])
    end

    it "no longer exposes cleanup! (it had no callers)" do
      expect(described_class).not_to respond_to(:cleanup!)
    end
  end

  describe "thread safety" do
    it "handles concurrent calls without errors" do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)

      threads = 10.times.map do |i|
        Thread.new do
          log = instance_double(
            RailsErrorDashboard::ErrorLog,
            error_hash: "hash_#{i}",
            error_type: "NoMethodError",
            occurrence_count: 1
          )
          described_class.should_notify?(log)
          described_class.record_notification(log)
          described_class.should_notify?(log)
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe ".environment_allowed?" do
    let(:staging_error) { instance_double(RailsErrorDashboard::ErrorLog, environment: "staging") }
    let(:legacy_error) { instance_double(RailsErrorDashboard::ErrorLog, environment: nil) }

    it "allows everything when notification_environments is nil" do
      RailsErrorDashboard.configuration.notification_environments = nil
      expect(described_class.environment_allowed?(staging_error)).to be true
    end

    it "allows an error whose environment is listed" do
      RailsErrorDashboard.configuration.notification_environments = %w[production staging]
      expect(described_class.environment_allowed?(staging_error)).to be true
    end

    it "rejects an error whose environment is not listed" do
      RailsErrorDashboard.configuration.notification_environments = %w[production]
      expect(described_class.environment_allowed?(staging_error)).to be false
    end

    it "treats a legacy NULL environment as the process environment" do
      RailsErrorDashboard.configuration.environment = "production"
      RailsErrorDashboard.configuration.notification_environments = %w[production]
      expect(described_class.environment_allowed?(legacy_error)).to be true

      RailsErrorDashboard.configuration.notification_environments = %w[staging]
      expect(described_class.environment_allowed?(legacy_error)).to be false
    end

    it "accepts a bare environment name, and nil for the process environment" do
      RailsErrorDashboard.configuration.environment = "uat"
      RailsErrorDashboard.configuration.notification_environments = %w[uat]
      expect(described_class.environment_allowed?("uat")).to be true
      expect(described_class.environment_allowed?("production")).to be false
      expect(described_class.environment_allowed?).to be true
    end

    it "fails open if the check itself raises" do
      allow(RailsErrorDashboard.configuration).to receive(:notification_environments).and_raise("boom")
      expect(described_class.environment_allowed?(staging_error)).to be true
    end
  end
end
