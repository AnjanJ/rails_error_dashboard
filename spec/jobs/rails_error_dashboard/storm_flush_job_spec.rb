# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::StormFlushJob do
  after { RailsErrorDashboard.reset_configuration! }

  describe "#perform" do
    it "stringifies entry keys before delegating to FlushStormCounts" do
      expect(RailsErrorDashboard::Commands::FlushStormCounts).to receive(:call).with(
        hash_including(
          entries: [ { "error_type" => "Boom", "count" => 3 } ],
          overflow: 0
        )
      )

      described_class.perform_now(entries: [ { error_type: "Boom", count: 3 } ])
    end

    it "stringifies episode keys before delegating" do
      expect(RailsErrorDashboard::Commands::FlushStormCounts).to receive(:call).with(
        hash_including(episode: { "started_at" => "2026-06-22T12:00:00Z" })
      )

      described_class.perform_now(entries: [], episode: { started_at: "2026-06-22T12:00:00Z" })
    end

    it "passes overflow through with empty entries" do
      expect(RailsErrorDashboard::Commands::FlushStormCounts).to receive(:call).with(
        hash_including(
          entries: [],
          overflow: 50,
          episode: { "started_at" => "2026-06-22T12:00:00Z" }
        )
      )

      described_class.perform_now(
        entries: [],
        overflow: 50,
        episode: { started_at: "2026-06-22T12:00:00Z" }
      )
    end

    it "leaves non-Hash entries untouched and does not raise" do
      expect(RailsErrorDashboard::Commands::FlushStormCounts).to receive(:call).with(
        hash_including(entries: [ "garbage", 123 ])
      )

      expect {
        described_class.perform_now(entries: [ "garbage", 123 ])
      }.not_to raise_error
    end

    context "when FlushStormCounts.call raises" do
      it "rescues the error and does not propagate it" do
        allow(RailsErrorDashboard::Commands::FlushStormCounts)
          .to receive(:call).and_raise(StandardError.new("db down"))

        expect {
          described_class.perform_now(entries: [ { error_type: "Boom" } ])
        }.not_to raise_error
      end
    end
  end
end
