# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::FindOrIncrementError do
  let!(:application) { create(:application) }

  let(:error_hash) { "abc123def456" }
  let(:attributes) do
    {
      application_id: application.id,
      error_type: "NoMethodError",
      message: "undefined method 'foo'",
      backtrace: "app/models/user.rb:10",
      platform: "Web",
      occurred_at: Time.current,
      error_hash: error_hash
    }
  end

  describe ".call" do
    context "when no existing error with the same hash" do
      it "creates a new error log" do
        expect {
          described_class.call(error_hash, attributes)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end

      it "returns the new error log" do
        result = described_class.call(error_hash, attributes)

        expect(result).to be_a(RailsErrorDashboard::ErrorLog)
        expect(result.error_type).to eq("NoMethodError")
        expect(result.message).to eq("undefined method 'foo'")
        expect(result.error_hash).to eq(error_hash)
      end

      it "sets resolved to false by default" do
        result = described_class.call(error_hash, attributes)

        expect(result.resolved).to be false
      end

      it "sets occurrence count to 1" do
        result = described_class.call(error_hash, attributes)

        expect(result.occurrence_count).to eq(1)
      end
    end

    context "when an existing unresolved error with the same hash exists" do
      let!(:existing_error) do
        create(:error_log,
          application: application,
          error_hash: error_hash,
          error_type: "NoMethodError",
          message: "undefined method 'foo'",
          occurrence_count: 3,
          occurred_at: 1.hour.ago,
          resolved: false)
      end

      it "does not create a new error log" do
        expect {
          described_class.call(error_hash, attributes)
        }.not_to change(RailsErrorDashboard::ErrorLog, :count)
      end

      it "increments occurrence count" do
        described_class.call(error_hash, attributes)

        existing_error.reload
        expect(existing_error.occurrence_count).to eq(4)
      end

      it "updates last_seen_at" do
        described_class.call(error_hash, attributes)

        existing_error.reload
        expect(existing_error.last_seen_at).to be_within(2.seconds).of(Time.current)
      end

      it "updates context from latest occurrence" do
        new_attrs = attributes.merge(
          user_id: 42,
          request_url: "https://example.com/new-page",
          ip_address: "10.0.0.1"
        )

        described_class.call(error_hash, new_attrs)

        existing_error.reload
        expect(existing_error.user_id).to eq(42)
        expect(existing_error.request_url).to eq("https://example.com/new-page")
        expect(existing_error.ip_address).to eq("10.0.0.1")
      end

      it "returns the existing error" do
        result = described_class.call(error_hash, attributes)

        expect(result.id).to eq(existing_error.id)
      end
    end

    context "when existing error is resolved" do
      let!(:resolved_error) do
        create(:error_log,
          application: application,
          error_hash: error_hash,
          error_type: "NoMethodError",
          occurrence_count: 5,
          occurred_at: 1.hour.ago,
          resolved: true)
      end

      it "creates a new error (resolved errors are considered fixed)" do
        expect {
          described_class.call(error_hash, attributes)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end
    end

    context "when existing error is older than 24 hours" do
      let!(:old_error) do
        create(:error_log,
          application: application,
          error_hash: error_hash,
          error_type: "NoMethodError",
          occurrence_count: 10,
          occurred_at: 25.hours.ago,
          resolved: false)
      end

      it "creates a new error" do
        expect {
          described_class.call(error_hash, attributes)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end
    end

    context "application scoping" do
      let!(:other_app) { create(:application, name: "OtherApp") }
      let!(:other_app_error) do
        create(:error_log,
          application: other_app,
          error_hash: error_hash,
          error_type: "NoMethodError",
          occurrence_count: 3,
          occurred_at: 1.hour.ago,
          resolved: false)
      end

      it "does not increment errors from other applications" do
        expect {
          described_class.call(error_hash, attributes)
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        other_app_error.reload
        expect(other_app_error.occurrence_count).to eq(3)
      end
    end
  end
end
