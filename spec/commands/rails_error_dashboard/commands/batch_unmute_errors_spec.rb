# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::BatchUnmuteErrors do
  describe ".call" do
    let!(:error1) { create(:error_log).tap { |e| e.update!(muted: true, muted_at: 1.hour.ago, muted_by: "gandalf", muted_reason: "known issue") } }
    let!(:error2) { create(:error_log).tap { |e| e.update!(muted: true, muted_at: 2.hours.ago, muted_by: "aragorn") } }
    let!(:error3) { create(:error_log).tap { |e| e.update!(muted: true, muted_at: 3.hours.ago) } }
    let(:error_ids) { [ error1.id, error2.id, error3.id ] }

    context "with valid error IDs" do
      it "unmutes all errors" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be true
        expect(result[:count]).to eq(3)
        expect(error1.reload.muted).to be false
        expect(error2.reload.muted).to be false
        expect(error3.reload.muted).to be false
      end

      it "clears mute metadata" do
        described_class.call(error_ids)

        error1.reload
        expect(error1.muted_at).to be_nil
        expect(error1.muted_by).to be_nil
        expect(error1.muted_reason).to be_nil
      end

      it "returns success result" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be true
        expect(result[:count]).to eq(3)
        expect(result[:total]).to eq(3)
        expect(result[:failed_ids]).to be_empty
        expect(result[:errors]).to be_empty
      end

      it "dispatches plugin event for unmuted errors" do
        expect(RailsErrorDashboard::PluginRegistry).to receive(:dispatch)
          .with(:on_errors_batch_unmuted, kind_of(Array))

        described_class.call(error_ids)
      end

      it "passes unmuted errors to plugin event" do
        unmuted_errors = nil
        allow(RailsErrorDashboard::PluginRegistry).to receive(:dispatch) do |event, errors|
          unmuted_errors = errors if event == :on_errors_batch_unmuted
        end

        described_class.call(error_ids)

        expect(unmuted_errors.map(&:id)).to match_array(error_ids)
      end
    end

    context "with empty error IDs array" do
      it "returns error result" do
        result = described_class.call([])

        expect(result[:success]).to be false
        expect(result[:count]).to eq(0)
        expect(result[:errors]).to include("No error IDs provided")
      end

      it "does not dispatch plugin event" do
        expect(RailsErrorDashboard::PluginRegistry).not_to receive(:dispatch)

        described_class.call([])
      end
    end

    context "with nil error IDs" do
      it "returns error result" do
        result = described_class.call(nil)

        expect(result[:success]).to be false
        expect(result[:count]).to eq(0)
        expect(result[:errors]).to include("No error IDs provided")
      end
    end

    context "with non-existent error IDs" do
      it "handles gracefully" do
        result = described_class.call([ 99999, 88888 ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(0)
        expect(result[:total]).to eq(2)
      end
    end

    context "with mix of valid and invalid IDs" do
      it "unmutes only valid errors" do
        result = described_class.call([ error1.id, 99999, error2.id ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(2)
        expect(result[:total]).to eq(3)
        expect(error1.reload.muted).to be false
        expect(error2.reload.muted).to be false
      end
    end

    context "with already unmuted errors" do
      let!(:unmuted_error) { create(:error_log) }

      it "handles gracefully" do
        result = described_class.call([ unmuted_error.id ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(1)
        expect(unmuted_error.reload.muted).to be false
      end
    end

    context "when database error occurs" do
      before do
        allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_raise(StandardError.new("Database error"))
      end

      it "returns error result" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be false
        expect(result[:count]).to eq(0)
        expect(result[:total]).to eq(3)
        expect(result[:errors]).to include("Database error")
      end

      it "logs the error" do
        allow(RailsErrorDashboard::Logger).to receive(:error)

        described_class.call(error_ids)

        expect(RailsErrorDashboard::Logger).to have_received(:error).with(/Batch unmute failed/)
      end
    end
  end
end
