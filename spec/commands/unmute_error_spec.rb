# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::UnmuteError do
  describe ".call" do
    let(:error_log) do
      create(:error_log).tap do |e|
        e.update!(muted: true, muted_at: 1.hour.ago, muted_by: "gandalf", muted_reason: "known issue")
      end
    end

    it "sets muted to false" do
      result = described_class.call(error_log.id)
      expect(result.muted).to be false
    end

    it "clears muted_at" do
      result = described_class.call(error_log.id)
      expect(result.muted_at).to be_nil
    end

    it "clears muted_by" do
      result = described_class.call(error_log.id)
      expect(result.muted_by).to be_nil
    end

    it "clears muted_reason" do
      result = described_class.call(error_log.id)
      expect(result.muted_reason).to be_nil
    end

    it "returns the updated error log" do
      result = described_class.call(error_log.id)
      expect(result).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result.id).to eq(error_log.id)
    end

    it "persists to the database" do
      described_class.call(error_log.id)
      expect(error_log.reload.muted).to be false
    end

    it "raises ActiveRecord::RecordNotFound for invalid id" do
      expect {
        described_class.call(-1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
