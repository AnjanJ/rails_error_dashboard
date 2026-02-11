# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow Commands" do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log,
      application: application,
      error_type: "TestError",
      message: "Something went wrong",
      status: "new",
      assigned_to: nil,
      assigned_at: nil,
      snoozed_until: nil,
      resolved: false)
  end

  describe RailsErrorDashboard::Commands::AssignError do
    describe ".call" do
      it "assigns the error to the given user" do
        result = described_class.call(error_log.id, assigned_to: "gandalf")

        expect(result.assigned_to).to eq("gandalf")
        expect(result.assigned_at).to be_within(1.second).of(Time.current)
      end

      it "auto-transitions status to in_progress" do
        result = described_class.call(error_log.id, assigned_to: "gandalf")

        expect(result.status).to eq("in_progress")
      end

      it "returns the updated error" do
        result = described_class.call(error_log.id, assigned_to: "gandalf")

        expect(result).to be_a(RailsErrorDashboard::ErrorLog)
        expect(result.id).to eq(error_log.id)
      end

      it "raises ActiveRecord::RecordNotFound for missing error" do
        expect {
          described_class.call(-1, assigned_to: "gandalf")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "persists the changes" do
        described_class.call(error_log.id, assigned_to: "aragorn")

        error_log.reload
        expect(error_log.assigned_to).to eq("aragorn")
        expect(error_log.status).to eq("in_progress")
      end
    end
  end

  describe RailsErrorDashboard::Commands::UnassignError do
    before do
      error_log.update!(assigned_to: "gandalf", assigned_at: 1.hour.ago, status: "in_progress")
    end

    describe ".call" do
      it "clears the assigned_to field" do
        result = described_class.call(error_log.id)

        expect(result.assigned_to).to be_nil
      end

      it "clears the assigned_at timestamp" do
        result = described_class.call(error_log.id)

        expect(result.assigned_at).to be_nil
      end

      it "returns the updated error" do
        result = described_class.call(error_log.id)

        expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      end

      it "persists the changes" do
        described_class.call(error_log.id)

        error_log.reload
        expect(error_log.assigned_to).to be_nil
        expect(error_log.assigned_at).to be_nil
      end
    end
  end

  describe RailsErrorDashboard::Commands::SnoozeError do
    describe ".call" do
      it "sets snoozed_until to the correct future time" do
        freeze_time do
          result = described_class.call(error_log.id, hours: 4)

          expect(result.snoozed_until).to be_within(1.second).of(4.hours.from_now)
        end
      end

      it "creates a comment when reason is provided" do
        expect {
          described_class.call(error_log.id, hours: 4, reason: "Waiting for deploy")
        }.to change { error_log.comments.count }.by(1)

        comment = error_log.comments.last
        expect(comment.body).to include("Snoozed for 4 hours")
        expect(comment.body).to include("Waiting for deploy")
      end

      it "uses assigned_to as comment author when assigned" do
        error_log.update!(assigned_to: "gandalf")

        described_class.call(error_log.id, hours: 1, reason: "Testing")

        comment = error_log.comments.last
        expect(comment.author_name).to eq("gandalf")
      end

      it "uses 'System' as comment author when unassigned" do
        described_class.call(error_log.id, hours: 1, reason: "Testing")

        comment = error_log.comments.last
        expect(comment.author_name).to eq("System")
      end

      it "does not create a comment when reason is nil" do
        expect {
          described_class.call(error_log.id, hours: 4)
        }.not_to change { error_log.comments.count }
      end

      it "does not create a comment when reason is blank" do
        expect {
          described_class.call(error_log.id, hours: 4, reason: "")
        }.not_to change { error_log.comments.count }
      end

      it "returns the updated error" do
        result = described_class.call(error_log.id, hours: 8)

        expect(result).to be_a(RailsErrorDashboard::ErrorLog)
        expect(result.snoozed_until).to be_present
      end
    end
  end

  describe RailsErrorDashboard::Commands::UnsnoozeError do
    before do
      error_log.update!(snoozed_until: 4.hours.from_now)
    end

    describe ".call" do
      it "clears the snoozed_until field" do
        result = described_class.call(error_log.id)

        expect(result.snoozed_until).to be_nil
      end

      it "returns the updated error" do
        result = described_class.call(error_log.id)

        expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      end

      it "persists the changes" do
        described_class.call(error_log.id)

        error_log.reload
        expect(error_log.snoozed_until).to be_nil
      end
    end
  end

  describe RailsErrorDashboard::Commands::UpdateErrorStatus do
    describe ".call" do
      context "with valid transition" do
        it "updates the status" do
          result = described_class.call(error_log.id, status: "in_progress")

          expect(result[:success]).to be true
          expect(result[:error].status).to eq("in_progress")
        end

        it "creates a comment when provided" do
          expect {
            described_class.call(error_log.id, status: "in_progress", comment: "Starting investigation")
          }.to change { error_log.comments.count }.by(1)

          comment = error_log.comments.last
          expect(comment.body).to include("Status changed to in_progress")
          expect(comment.body).to include("Starting investigation")
        end

        it "does not create a comment when comment is nil" do
          expect {
            described_class.call(error_log.id, status: "in_progress")
          }.not_to change { error_log.comments.count }
        end

        it "auto-resolves when transitioning to resolved" do
          # Move to in_progress first (valid transition from new)
          described_class.call(error_log.id, status: "in_progress")
          # Then to investigating
          described_class.call(error_log.id, status: "investigating")
          # Then to resolved
          result = described_class.call(error_log.id, status: "resolved")

          expect(result[:success]).to be true
          expect(result[:error].resolved).to be true
        end

        it "uses assigned_to as comment author" do
          error_log.update!(assigned_to: "legolas")

          described_class.call(error_log.id, status: "in_progress", comment: "On it")

          comment = error_log.comments.last
          expect(comment.author_name).to eq("legolas")
        end

        it "uses 'System' as comment author when unassigned" do
          described_class.call(error_log.id, status: "in_progress", comment: "Auto-assigned")

          comment = error_log.comments.last
          expect(comment.author_name).to eq("System")
        end
      end

      context "with invalid transition" do
        it "returns success: false" do
          # new → resolved is not a valid transition
          result = described_class.call(error_log.id, status: "resolved")

          expect(result[:success]).to be false
        end

        it "does not change the status" do
          described_class.call(error_log.id, status: "resolved")

          error_log.reload
          expect(error_log.status).to eq("new")
        end

        it "does not create a comment" do
          expect {
            described_class.call(error_log.id, status: "resolved", comment: "Should not be saved")
          }.not_to change { error_log.comments.count }
        end
      end
    end
  end
end
