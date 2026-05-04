# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsErrorDashboard::Services::CascadeDetector do
  describe ".call" do
    let(:parent_error) { create(:error_log, error_type: "DatabaseError") }
    let(:child_error) { create(:error_log, error_type: "NoMethodError") }
    let(:unrelated_error) { create(:error_log, error_type: "UnrelatedError") }

    before do
      # Create a cascade pattern: parent_error → child_error
      # Parent error occurs, then child error 30 seconds later (within 60s window)
      base_time = 2.hours.ago

      # Create 5 cascades (parent → child within 60s)
      5.times do |i|
        parent_time = base_time + (i * 10.minutes)
        child_time = parent_time + 30.seconds

        create(:error_occurrence, error_log: parent_error, occurred_at: parent_time)
        create(:error_occurrence, error_log: child_error, occurred_at: child_time)
      end

      # Create some unrelated occurrences (outside 60s window)
      create(:error_occurrence, error_log: unrelated_error, occurred_at: base_time + 2.minutes)
    end

    it "detects cascade patterns" do
      result = described_class.call(lookback_hours: 24)

      expect(result[:detected]).to be > 0
    end

    it "returns detected and updated counts" do
      result = described_class.call(lookback_hours: 24)

      expect(result).to have_key(:detected)
      expect(result).to have_key(:updated)
      expect(result[:detected]).to be_a(Integer)
      expect(result[:updated]).to be_a(Integer)
    end

    it "creates cascade pattern for frequent cascades" do
      expect {
        described_class.call(lookback_hours: 24)
      }.to change { RailsErrorDashboard::CascadePattern.count }

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: parent_error,
        child_error: child_error
      )

      expect(pattern).to be_present
      expect(pattern.frequency).to be >= 3
    end

    it "calculates average delay" do
      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: parent_error,
        child_error: child_error
      )

      expect(pattern.avg_delay_seconds).to be_within(5).of(30.0)
    end

    it "does not create patterns for infrequent cascades" do
      # Create only 2 occurrences (below MIN_CASCADE_FREQUENCY of 3)
      infrequent_parent = create(:error_log, error_type: "InfrequentParent")
      infrequent_child = create(:error_log, error_type: "InfrequentChild")

      2.times do |i|
        parent_time = 1.hour.ago + (i * 10.minutes)
        child_time = parent_time + 15.seconds

        create(:error_occurrence, error_log: infrequent_parent, occurred_at: parent_time)
        create(:error_occurrence, error_log: infrequent_child, occurred_at: child_time)
      end

      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: infrequent_parent,
        child_error: infrequent_child
      )

      expect(pattern).to be_nil
    end

    it "does not create patterns for errors outside detection window" do
      # Create occurrences 2 minutes apart (outside 60s window)
      distant_parent = create(:error_log, error_type: "DistantParent")
      distant_child = create(:error_log, error_type: "DistantChild")

      5.times do |i|
        parent_time = 1.hour.ago + (i * 10.minutes)
        child_time = parent_time + 2.minutes

        create(:error_occurrence, error_log: distant_parent, occurred_at: parent_time)
        create(:error_occurrence, error_log: distant_child, occurred_at: child_time)
      end

      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: distant_parent,
        child_error: distant_child
      )

      expect(pattern).to be_nil
    end

    it "updates existing patterns on subsequent runs" do
      # First run - creates pattern
      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: parent_error,
        child_error: child_error
      )
      initial_frequency = pattern.frequency

      # Create more cascades
      3.times do |i|
        parent_time = 30.minutes.ago + (i * 5.minutes)
        child_time = parent_time + 25.seconds

        create(:error_occurrence, error_log: parent_error, occurred_at: parent_time)
        create(:error_occurrence, error_log: child_error, occurred_at: child_time)
      end

      # Second run - updates pattern
      result = described_class.call(lookback_hours: 24)

      expect(result[:updated]).to be > 0

      pattern.reload
      expect(pattern.frequency).to be > initial_frequency
    end

    it "calculates probability for detected patterns" do
      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: parent_error,
        child_error: child_error
      )

      expect(pattern.cascade_probability).to be_present
      expect(pattern.cascade_probability).to be_between(0.0, 1.0)
    end

    it "sets last_detected_at timestamp" do
      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: parent_error,
        child_error: child_error
      )

      expect(pattern.last_detected_at).to be_within(1.minute).of(Time.current)
    end

    it "respects lookback_hours parameter" do
      # Create old cascades (outside lookback window)
      old_parent = create(:error_log, error_type: "OldParent")
      old_child = create(:error_log, error_type: "OldChild")

      5.times do |i|
        parent_time = 48.hours.ago + (i * 10.minutes)
        child_time = parent_time + 30.seconds

        create(:error_occurrence, error_log: old_parent, occurred_at: parent_time)
        create(:error_occurrence, error_log: old_child, occurred_at: child_time)
      end

      # Only look back 24 hours
      described_class.call(lookback_hours: 24)

      pattern = RailsErrorDashboard::CascadePattern.find_by(
        parent_error: old_parent,
        child_error: old_child
      )

      # Should not detect old cascades
      expect(pattern).to be_nil
    end

    it "handles case with no error occurrences gracefully" do
      # Delete all occurrences
      RailsErrorDashboard::ErrorOccurrence.delete_all

      expect {
        result = described_class.call(lookback_hours: 24)
        expect(result[:detected]).to eq(0)
        expect(result[:updated]).to eq(0)
      }.not_to raise_error
    end

    it "returns zeros if CascadePattern table doesn't exist" do
      allow(RailsErrorDashboard::CascadePattern).to receive(:table_exists?).and_return(false)

      result = described_class.call(lookback_hours: 24)

      expect(result[:detected]).to eq(0)
      expect(result[:updated]).to eq(0)
    end

    it "returns zeros if ErrorOccurrence table doesn't exist" do
      allow(RailsErrorDashboard::ErrorOccurrence).to receive(:table_exists?).and_return(false)

      result = described_class.call(lookback_hours: 24)

      expect(result[:detected]).to eq(0)
      expect(result[:updated]).to eq(0)
    end

    it "issues O(1) SQL queries regardless of occurrence count" do
      # Regression: the original implementation ran one inner SQL query per
      # parent occurrence to find children in the time window. With N
      # occurrences in the lookback window we issued N+1 queries, scaling
      # linearly with traffic. The fix loads (error_log_id, occurred_at)
      # once via pluck and walks the sorted array with a two-pointer sweep.
      #
      # The before block creates ~10 occurrences. Pre-fix this method would
      # have issued ~11 read queries on error_occurrences. The fix should
      # issue one — but we tolerate up to 2 to allow for one schema-cache
      # check on cold runs in the spec environment.
      query_count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        next if payload[:name] == "SCHEMA"
        next if payload[:sql].include?("schema_migrations")
        query_count += 1 if payload[:sql].include?('"rails_error_dashboard_error_occurrences"')
      end

      described_class.call(lookback_hours: 24)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(query_count).to be <= 2
    end

    it "treats simultaneous (same-timestamp) occurrences as not cascading" do
      # Regression for parity with the original SQL-based algorithm which
      # used `occurred_at > ?` (strictly greater). Two occurrences at the
      # exact same instant on different error_log_ids should not register
      # as a cascade pair — neither is "after" the other.
      same_time = 30.minutes.ago
      simultaneous_a = create(:error_log, error_type: "SimErrorA")
      simultaneous_b = create(:error_log, error_type: "SimErrorB")

      3.times do
        create(:error_occurrence, error_log: simultaneous_a, occurred_at: same_time)
        create(:error_occurrence, error_log: simultaneous_b, occurred_at: same_time)
      end

      RailsErrorDashboard::CascadePattern.delete_all
      described_class.call(lookback_hours: 1)

      simultaneous_pair = RailsErrorDashboard::CascadePattern.where(
        parent_error_id: simultaneous_a.id,
        child_error_id: simultaneous_b.id
      )
      expect(simultaneous_pair).to be_empty
    end
  end
end
