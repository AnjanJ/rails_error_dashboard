# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::BatchDeleteErrors do
  describe ".call" do
    let!(:error1) { create(:error_log) }
    let!(:error2) { create(:error_log) }
    let!(:error3) { create(:error_log) }
    let(:error_ids) { [ error1.id, error2.id, error3.id ] }

    context "with valid error IDs" do
      it "deletes all errors" do
        expect {
          described_class.call(error_ids)
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-3)
      end

      it "removes errors from database" do
        described_class.call(error_ids)

        expect(RailsErrorDashboard::ErrorLog.find_by(id: error1.id)).to be_nil
        expect(RailsErrorDashboard::ErrorLog.find_by(id: error2.id)).to be_nil
        expect(RailsErrorDashboard::ErrorLog.find_by(id: error3.id)).to be_nil
      end

      it "returns success result" do
        result = described_class.call(error_ids)

        expect(result[:success]).to be true
        expect(result[:count]).to eq(3)
        expect(result[:total]).to eq(3)
        expect(result[:errors]).to be_empty
      end

      it "dispatches plugin event for deleted errors" do
        expect(RailsErrorDashboard::PluginRegistry).to receive(:dispatch)
          .with(:on_errors_batch_deleted, kind_of(Array))

        described_class.call(error_ids)
      end

      it "passes deleted error IDs to plugin event" do
        deleted_ids = nil
        allow(RailsErrorDashboard::PluginRegistry).to receive(:dispatch) do |event, ids|
          deleted_ids = ids if event == :on_errors_batch_deleted
        end

        described_class.call(error_ids)

        expect(deleted_ids).to match_array(error_ids)
      end
    end

    context "with empty error IDs array" do
      it "returns error result" do
        result = described_class.call([])

        expect(result[:success]).to be false
        expect(result[:count]).to eq(0)
        expect(result[:errors]).to include("No error IDs provided")
      end

      it "does not delete any errors" do
        expect {
          described_class.call([])
        }.not_to change { RailsErrorDashboard::ErrorLog.count }
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

      it "does not raise error" do
        expect {
          described_class.call([ 99999 ])
        }.not_to raise_error
      end
    end

    context "with mix of valid and invalid IDs" do
      it "deletes only valid errors" do
        expect {
          described_class.call([ error1.id, 99999, error2.id ])
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-2)
      end

      it "returns correct count" do
        result = described_class.call([ error1.id, 99999, error2.id ])

        expect(result[:count]).to eq(2)
        expect(result[:total]).to eq(3)
      end

      it "dispatches event only for existing errors" do
        deleted_ids = nil
        allow(RailsErrorDashboard::PluginRegistry).to receive(:dispatch) do |event, ids|
          deleted_ids = ids if event == :on_errors_batch_deleted
        end

        described_class.call([ error1.id, 99999, error2.id ])

        expect(deleted_ids).to match_array([ error1.id, error2.id ])
        expect(deleted_ids).not_to include(99999)
      end
    end

    context "with duplicate error IDs" do
      it "deletes each error once" do
        expect {
          described_class.call([ error1.id, error1.id, error2.id ])
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-2)
      end

      it "returns correct count" do
        result = described_class.call([ error1.id, error1.id, error2.id ])

        expect(result[:count]).to eq(2)
      end
    end

    context "with error IDs as strings" do
      it "handles string IDs" do
        result = described_class.call([ error1.id.to_s, error2.id.to_s ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(2)
      end

      it "deletes the errors" do
        expect {
          described_class.call([ error1.id.to_s, error2.id.to_s ])
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-2)
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

        expect(RailsErrorDashboard::Logger).to have_received(:error).with(/Batch delete failed/)
      end

      it "does not delete any errors" do
        expect {
          described_class.call(error_ids)
        }.not_to change { RailsErrorDashboard::ErrorLog.count }
      end
    end

    context "with single error ID" do
      it "deletes one error" do
        expect {
          described_class.call([ error1.id ])
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-1)
      end

      it "returns success" do
        result = described_class.call([ error1.id ])

        expect(result[:success]).to be true
        expect(result[:count]).to eq(1)
      end
    end

    context "with all errors in database" do
      it "can delete all errors" do
        all_ids = RailsErrorDashboard::ErrorLog.pluck(:id)

        expect {
          described_class.call(all_ids)
        }.to change { RailsErrorDashboard::ErrorLog.count }.to(0)
      end
    end

    context "with resolved errors" do
      before do
        error1.update!(resolved: true, resolved_at: Time.current)
      end

      it "deletes resolved errors" do
        expect {
          described_class.call([ error1.id ])
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-1)
      end
    end

    context "with unresolved errors" do
      before do
        error1.update!(resolved: false)
      end

      it "deletes unresolved errors" do
        expect {
          described_class.call([ error1.id ])
        }.to change { RailsErrorDashboard::ErrorLog.count }.by(-1)
      end
    end
  end
end
