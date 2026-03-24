# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::MuteError do
  describe ".call" do
    let(:error_log) { create(:error_log) }

    it "sets the muted flag to true" do
      result = described_class.call(error_log.id)
      expect(result.muted).to be true
    end

    it "sets muted_at timestamp" do
      freeze_time do
        result = described_class.call(error_log.id)
        expect(result.muted_at).to be_within(1.second).of(Time.current)
      end
    end

    it "sets muted_by when provided" do
      result = described_class.call(error_log.id, muted_by: "gandalf")
      expect(result.muted_by).to eq("gandalf")
    end

    it "sets muted_reason when provided" do
      result = described_class.call(error_log.id, reason: "known scanner noise")
      expect(result.muted_reason).to eq("known scanner noise")
    end

    it "creates a comment when reason is provided" do
      expect {
        described_class.call(error_log.id, reason: "expected error from bots")
      }.to change(RailsErrorDashboard::ErrorComment, :count).by(1)
    end

    it "sets comment body with mute details" do
      described_class.call(error_log.id, muted_by: "gandalf", reason: "known issue")
      comment = error_log.comments.last
      expect(comment.body).to include("Muted notifications")
      expect(comment.body).to include("known issue")
      expect(comment.author_name).to eq("gandalf")
    end

    it "uses System as comment author when muted_by is not provided" do
      error_log.update!(assigned_to: "aragorn")
      described_class.call(error_log.id, reason: "test")
      comment = error_log.comments.last
      # Does not fall back to assigned_to — the assignee may not be the person muting
      expect(comment.author_name).to eq("System")
    end

    it "does not create a comment when no reason is provided" do
      expect {
        described_class.call(error_log.id)
      }.not_to change(RailsErrorDashboard::ErrorComment, :count)
    end

    it "returns the updated error log" do
      result = described_class.call(error_log.id)
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it "persists the muted flag to the database" do
      described_class.call(error_log.id)
      expect(error_log.reload.muted).to be true
    end

    it "raises ActiveRecord::RecordNotFound for invalid id" do
      expect {
        described_class.call(-1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
