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
    context "when retention_days is nil (disabled)" do
      before do
        RailsErrorDashboard.configuration.retention_days = nil
      end

      it "does not delete any errors" do
        old_error = create(:error_log, occurred_at: 1.year.ago)
        described_class.new.perform
        expect(RailsErrorDashboard::ErrorLog.exists?(old_error.id)).to be true
      end

      it "returns 0" do
        create(:error_log, occurred_at: 1.year.ago)
        expect(described_class.new.perform).to eq(0)
      end
    end

    context "with default retention_days (90)" do
      it "deletes errors older than 90 days" do
        old_error = create(:error_log, occurred_at: 91.days.ago)
        recent_error = create(:error_log, occurred_at: 89.days.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(old_error.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(recent_error.id)).to be true
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

      it "cleans up associated cascade patterns (as parent)" do
        old_error = create(:error_log, occurred_at: 60.days.ago)
        other_error = create(:error_log, occurred_at: 1.day.ago)
        RailsErrorDashboard::CascadePattern.create!(
          parent_error: old_error,
          child_error: other_error,
          frequency: 1,
          cascade_probability: 0.5
        )

        expect {
          described_class.new.perform
        }.to change(RailsErrorDashboard::CascadePattern, :count).by(-1)
      end

      it "cleans up associated cascade patterns (as child)" do
        old_error = create(:error_log, occurred_at: 60.days.ago)
        other_error = create(:error_log, occurred_at: 1.day.ago)
        RailsErrorDashboard::CascadePattern.create!(
          parent_error: other_error,
          child_error: old_error,
          frequency: 1,
          cascade_probability: 0.5
        )

        expect {
          described_class.new.perform
        }.to change(RailsErrorDashboard::CascadePattern, :count).by(-1)
      end

      it "handles empty tables gracefully" do
        expect { described_class.new.perform }.not_to raise_error
      end

      it "returns 0 when no expired records exist" do
        create(:error_log, occurred_at: 1.day.ago)
        expect(described_class.new.perform).to eq(0)
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

    # occurred_at is when a group was FIRST seen and never moves. Expiring by
    # it deleted errors that were still happening today, together with their
    # comments and triage history, the day they turned retention_days old.
    context "an error that is still occurring" do
      before { RailsErrorDashboard.configuration.retention_days = 90 }

      it "is kept, with its occurrences and comments, however old its first occurrence is" do
        live = create(:error_log, occurred_at: 120.days.ago, last_seen_at: Time.current)
        occurrence = create(:error_occurrence, error_log: live, occurred_at: 1.hour.ago)
        comment = RailsErrorDashboard::ErrorComment.create!(error_log: live, author_name: "ann", body: "known issue")

        expect(described_class.new.perform).to eq(0)

        expect(RailsErrorDashboard::ErrorLog.exists?(live.id)).to be true
        expect(RailsErrorDashboard::ErrorOccurrence.exists?(occurrence.id)).to be true
        expect(RailsErrorDashboard::ErrorComment.exists?(comment.id)).to be true
      end

      it "is deleted once it has not been seen for retention_days" do
        stale = create(:error_log, occurred_at: 120.days.ago, last_seen_at: 100.days.ago)

        expect(described_class.new.perform).to eq(1)
        expect(RailsErrorDashboard::ErrorLog.exists?(stale.id)).to be false
      end

      it "falls back to occurred_at for a legacy row with no last_seen_at" do
        legacy_old = create(:error_log, occurred_at: 120.days.ago)
        legacy_old.update_columns(last_seen_at: nil)
        legacy_recent = create(:error_log, occurred_at: 10.days.ago)
        legacy_recent.update_columns(last_seen_at: nil)

        described_class.new.perform

        expect(RailsErrorDashboard::ErrorLog.exists?(legacy_old.id)).to be false
        expect(RailsErrorDashboard::ErrorLog.exists?(legacy_recent.id)).to be true
      end
    end

    # Both tables are written independently of error logs, and nothing else
    # ever deletes from them.
    context "diagnostic dumps and swallowed exceptions" do
      before { RailsErrorDashboard.configuration.retention_days = 90 }

      let(:application) { create(:application) }

      def dump(captured_at)
        RailsErrorDashboard::DiagnosticDump.create!(
          application_id: application.id, dump_data: "{}", captured_at: captured_at
        )
      end

      it "prunes expired rows even when no error log is expired" do
        create(:error_log, occurred_at: 1.day.ago)
        old_dump = dump(120.days.ago)
        new_dump = dump(1.day.ago)
        old_swallowed = create(:swallowed_exception, application: application, period_hour: 120.days.ago.beginning_of_hour)
        new_swallowed = create(:swallowed_exception, application: application, period_hour: 1.day.ago.beginning_of_hour)

        expect(described_class.new.perform).to eq(0)

        expect(RailsErrorDashboard::DiagnosticDump.exists?(old_dump.id)).to be false
        expect(RailsErrorDashboard::DiagnosticDump.exists?(new_dump.id)).to be true
        expect(RailsErrorDashboard::SwallowedException.exists?(old_swallowed.id)).to be false
        expect(RailsErrorDashboard::SwallowedException.exists?(new_swallowed.id)).to be true
      end

      it "prunes them whether or not the feature that wrote them is still enabled" do
        RailsErrorDashboard.configuration.enable_swallowed_exception_tracking = false if
          RailsErrorDashboard.configuration.respond_to?(:enable_swallowed_exception_tracking=)
        old_swallowed = create(:swallowed_exception, application: application, period_hour: 120.days.ago.beginning_of_hour)

        described_class.new.perform

        expect(RailsErrorDashboard::SwallowedException.exists?(old_swallowed.id)).to be false
      end

      it "still cleans up error logs when pruning one of these tables fails" do
        allow(RailsErrorDashboard::DiagnosticDump).to receive(:where).and_raise(ActiveRecord::StatementInvalid, "boom")
        expired = create(:error_log, occurred_at: 120.days.ago, last_seen_at: 120.days.ago)

        expect(described_class.new.perform).to eq(1)
        expect(RailsErrorDashboard::ErrorLog.exists?(expired.id)).to be false
      end

      it "does nothing to them when retention is disabled" do
        RailsErrorDashboard.configuration.retention_days = nil
        old_dump = dump(120.days.ago)

        described_class.new.perform

        expect(RailsErrorDashboard::DiagnosticDump.exists?(old_dump.id)).to be true
      end
    end
  end

  describe "job configuration" do
    it "is enqueued to the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
