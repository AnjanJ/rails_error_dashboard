# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::BatchMuteErrors do
  describe ".call" do
    let!(:error1) { create(:error_log) }
    let!(:error2) { create(:error_log) }
    let!(:error3) { create(:error_log) }
    let(:error_ids) { [ error1.id, error2.id, error3.id ] }

    context "with valid error IDs" do
      it "mutes all errors" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be true
        expect(result[:count]).to eq(3)
        expect(error1.reload.muted).to be true
        expect(error2.reload.muted).to be true
        expect(error3.reload.muted).to be true
      end

      it "sets muted_at timestamp" do
        freeze_time do
          described_class.call(error_ids)

          expect(error1.reload.muted_at).to be_within(1.second).of(Time.current)
          expect(error2.reload.muted_at).to be_within(1.second).of(Time.current)
        end
      end

      it "returns success result" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be true
        expect(result[:count]).to eq(3)
        expect(result[:total]).to eq(3)
        expect(result[:failed_ids]).to be_empty
        expect(result[:errors]).to be_empty
      end

      context "with muted_by" do
        it "sets the muter name" do
          described_class.call(error_ids, muted_by: "gandalf")

          expect(error1.reload.muted_by).to eq("gandalf")
          expect(error2.reload.muted_by).to eq("gandalf")
          expect(error3.reload.muted_by).to eq("gandalf")
        end
      end

      it "dispatches plugin event for muted errors" do
        expect(RailsErrorDashboard::PluginRegistry).to receive(:dispatch)
          .with(:on_errors_batch_muted, kind_of(Array))

        described_class.call(error_ids)
      end

      it "passes muted errors to plugin event" do
        muted_errors = nil
        allow(RailsErrorDashboard::PluginRegistry).to receive(:dispatch) do |event, errors|
          muted_errors = errors if event == :on_errors_batch_muted
        end

        described_class.call(error_ids)

        expect(muted_errors.map(&:id)).to match_array(error_ids)
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
      it "mutes only valid errors" do
        result = described_class.call([ error1.id, 99999, error2.id ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(2)
        expect(result[:total]).to eq(3)
        expect(error1.reload.muted).to be true
        expect(error2.reload.muted).to be true
      end
    end

    context "with duplicate error IDs" do
      it "mutes each error once" do
        result = described_class.call([ error1.id, error1.id, error2.id ])

        expect(result[:count]).to eq(2)
        expect(error1.reload.muted).to be true
        expect(error2.reload.muted).to be true
      end
    end

    context "with error IDs as strings" do
      it "handles string IDs" do
        result = described_class.call([ error1.id.to_s, error2.id.to_s ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(2)
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

        expect(RailsErrorDashboard::Logger).to have_received(:error).with(/Batch mute failed/)
      end
    end

    context "with already muted errors" do
      before do
        error1.update!(muted: true, muted_at: 1.day.ago, muted_by: "aragorn")
      end

      it "updates mute details" do
        described_class.call([ error1.id ], muted_by: "gandalf")

        expect(error1.reload.muted_by).to eq("gandalf")
        expect(error1.reload.muted_at).to be > 1.day.ago
      end
    end
  end
end
