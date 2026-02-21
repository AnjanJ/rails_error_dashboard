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

  describe ".cleanup!" do
    it "removes entries older than max_age_hours" do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)

      # Record a notification "25 hours ago"
      travel_to(25.hours.ago) do
        described_class.record_notification(error_log)
      end

      # After cleanup, it should allow notifications again
      described_class.cleanup!(max_age_hours: 24)
      expect(described_class.should_notify?(error_log)).to be true
    end

    it "preserves recent entries" do
      allow(RailsErrorDashboard::Services::SeverityClassifier).to receive(:classify)
        .with("NoMethodError").and_return(:high)

      described_class.record_notification(error_log)
      described_class.cleanup!(max_age_hours: 24)

      # Recent entry should still be in cooldown
      expect(described_class.should_notify?(error_log)).to be false
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
end
