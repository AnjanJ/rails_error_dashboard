# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::RetentionCleanupJob, type: :job do
  before do
    RailsErrorDashboard.configure do |config|
      config.async_logging = false
    end
  end

  after do
    RailsErrorDashboard.reset_configuration!
  end

  describe "#perform" do
    context "when retention_days is nil (default)" do
      before do
        RailsErrorDashboard.configuration.retention_days = nil
      end

      it "does not delete any errors" do
        old_error = create(:error_log, occurred_at: 1.year.ago)
        described_class.new.perform
        expect(RailsErrorDashboard::ErrorLog.exists?(old_error.id)).to be true
      end
    end

    context "when retention_days is configured" do
      before do
        RailsErrorDashboard.configuration.retention_days = 30
      end

      it "deletes errors older than retention_days" do
        old_error = create(:error_log, occurred_at: 31.days.ago)
        recent_error = create(:error_log, occurred_at: 29.days.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(old_error.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(recent_error.id)).to be true
      end

      it "deletes errors exactly at the boundary" do
        boundary_error = create(:error_log, occurred_at: 30.days.ago - 1.minute)
        just_inside = create(:error_log, occurred_at: 30.days.ago + 1.minute)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(boundary_error.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(just_inside.id)).to be true
      end

      it "deletes both resolved and unresolved old errors" do
        old_resolved = create(:error_log, :resolved, occurred_at: 60.days.ago)
        old_unresolved = create(:error_log, occurred_at: 60.days.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(old_resolved.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(old_unresolved.id)).to be false
      end

      it "cleans up associated error_occurrences" do
        old_error = create(:error_log, occurred_at: 60.days.ago)
        RailsErrorDashboard::ErrorOccurrence.create!(
          error_log: old_error,
          occurred_at: 60.days.ago
        )

        expect {
          described_class.new.perform
        }.to change(RailsErrorDashboard::ErrorOccurrence, :count).by(-1)
      end

      it "cleans up associated error_comments" do
        old_error = create(:error_log, occurred_at: 60.days.ago)
        RailsErrorDashboard::ErrorComment.create!(
          error_log: old_error,
          author_name: "Test",
          body: "A comment"
        )

        expect {
          described_class.new.perform
        }.to change(RailsErrorDashboard::ErrorComment, :count).by(-1)
      end

      it "handles empty tables gracefully" do
        expect { described_class.new.perform }.not_to raise_error
      end

      it "returns the count of deleted errors" do
        create(:error_log, occurred_at: 60.days.ago)
        create(:error_log, occurred_at: 60.days.ago)
        create(:error_log, occurred_at: 1.day.ago)

        result = described_class.new.perform
        expect(result).to eq(2)
      end
    end

    context "with different retention_days values" do
      it "respects 7-day retention" do
        RailsErrorDashboard.configuration.retention_days = 7

        old = create(:error_log, occurred_at: 8.days.ago)
        recent = create(:error_log, occurred_at: 6.days.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(old.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(recent.id)).to be true
      end

      it "respects 365-day retention" do
        RailsErrorDashboard.configuration.retention_days = 365

        old = create(:error_log, occurred_at: 366.days.ago)
        recent = create(:error_log, occurred_at: 364.days.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(old.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(recent.id)).to be true
      end
    end

    context "batch deletion safety" do
      before do
        RailsErrorDashboard.configuration.retention_days = 30
      end

      it "deletes large numbers of records without error" do
        5.times { create(:error_log, occurred_at: 60.days.ago) }
        keep = create(:error_log, occurred_at: 1.day.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.count).to eq(1)
        expect(RailsErrorDashboard::ErrorLog.first).to eq(keep)
      end
    end
  end

  describe "job configuration" do
    it "is enqueued to the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
