# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::BatchResolveErrors do
  describe ".call" do
    let!(:error1) { create(:error_log, resolved: false) }
    let!(:error2) { create(:error_log, resolved: false) }
    let!(:error3) { create(:error_log, resolved: false) }
    let(:error_ids) { [ error1.id, error2.id, error3.id ] }

    context "with valid error IDs" do
      it "resolves all errors" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be true
        expect(result[:count]).to eq(3)
        expect(error1.reload.resolved).to be true
        expect(error2.reload.resolved).to be true
        expect(error3.reload.resolved).to be true
      end

      it "sets resolved_at timestamp" do
        freeze_time do
          described_class.call(error_ids)

          expect(error1.reload.resolved_at).to be_within(1.second).of(Time.current)
          expect(error2.reload.resolved_at).to be_within(1.second).of(Time.current)
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

      context "with resolved_by_name" do
        it "sets the resolver name" do
          described_class.call(error_ids, resolved_by_name: "John Doe")

          expect(error1.reload.resolved_by_name).to eq("John Doe")
          expect(error2.reload.resolved_by_name).to eq("John Doe")
          expect(error3.reload.resolved_by_name).to eq("John Doe")
        end
      end

      context "with resolution_comment" do
        it "sets the resolution comment" do
          comment = "Fixed in PR #123"
          described_class.call(error_ids, resolution_comment: comment)

          expect(error1.reload.resolution_comment).to eq(comment)
          expect(error2.reload.resolution_comment).to eq(comment)
          expect(error3.reload.resolution_comment).to eq(comment)
        end
      end

      context "with both resolved_by_name and resolution_comment" do
        it "sets both fields" do
          result = described_class.call(
            error_ids,
            resolved_by_name: "Jane Smith",
            resolution_comment: "Deployed hotfix"
          )

          expect(result[:success]).to be true
          expect(error1.reload.resolved_by_name).to eq("Jane Smith")
          expect(error1.reload.resolution_comment).to eq("Deployed hotfix")
        end
      end

      it "dispatches plugin event for resolved errors" do
        expect(RailsErrorDashboard::PluginRegistry).to receive(:dispatch)
          .with(:on_errors_batch_resolved, kind_of(Array))

        described_class.call(error_ids)
      end

      it "passes resolved errors to plugin event" do
        resolved_errors = nil
        allow(RailsErrorDashboard::PluginRegistry).to receive(:dispatch) do |event, errors|
          resolved_errors = errors if event == :on_errors_batch_resolved
        end

        described_class.call(error_ids)

        expect(resolved_errors.map(&:id)).to match_array(error_ids)
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
      it "resolves only valid errors" do
        result = described_class.call([ error1.id, 99999, error2.id ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(2)
        expect(result[:total]).to eq(3)
        expect(error1.reload.resolved).to be true
        expect(error2.reload.resolved).to be true
      end
    end

    context "with duplicate error IDs" do
      it "resolves each error once" do
        result = described_class.call([ error1.id, error1.id, error2.id ])

        expect(result[:count]).to eq(2)
        expect(error1.reload.resolved).to be true
        expect(error2.reload.resolved).to be true
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

        expect(RailsErrorDashboard::Logger).to have_received(:error).with(/Batch resolve failed/)
      end
    end

    context "with already resolved errors" do
      before do
        error1.update!(resolved: true, resolved_at: 1.day.ago)
      end

      it "updates resolution details" do
        described_class.call([ error1.id ], resolution_comment: "New resolution")

        expect(error1.reload.resolution_comment).to eq("New resolution")
      end
    end
  end
end
