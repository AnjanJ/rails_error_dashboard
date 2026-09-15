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

    context "when the error store is unreachable" do
      # Storm counts exist only in one process's memory until this job writes
      # them. Acknowledging a batch that wrote nothing loses them outright, so
      # the job fails and Active Job retries it.
      #
      # Two layers, asserted separately on purpose: #perform is where the
      # failure is raised, and perform_now is where retry_on catches it and
      # schedules another attempt. Asserting a raise from perform_now would
      # pass only while retry_on is broken.
      it "raises out of #perform when the store cannot be reached" do
        allow(RailsErrorDashboard::Commands::FlushStormCounts)
          .to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished.new("db down"))

        expect {
          described_class.new.perform(entries: [ { error_type: "Boom" } ])
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it "schedules a retry rather than acknowledging the batch" do
        allow(RailsErrorDashboard::Commands::FlushStormCounts)
          .to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished.new("db down"))

        # Read THIS job's adapter, not ActiveJob::Base's. A spec that swaps a
        # job class's adapter gives it its own TestAdapter instance, and the
        # enqueued_jobs helper keeps reading the base one -- so the retry lands
        # in a queue the helper cannot see, and only under some orderings.
        expect {
          described_class.perform_now(entries: [ { error_type: "Boom" } ])
        }.to change { described_class.queue_adapter.enqueued_jobs.count { |j| j[:job] == described_class } }.by(1)
      end

      it "raises out of #perform when the command reports that nothing reconciled" do
        allow(RailsErrorDashboard::Commands::FlushStormCounts)
          .to receive(:call).and_return({ success: false, reconciled: 0, failed: 2, error: "all 2 entries failed to reconcile" })

        expect {
          described_class.new.perform(entries: [ { error_type: "Boom" } ])
        }.to raise_error(described_class::FlushFailed, /reconciled nothing/)
      end
    end

    context "when the batch partly succeeded" do
      it "acknowledges it — replaying would double the counts already written" do
        allow(RailsErrorDashboard::Commands::FlushStormCounts)
          .to receive(:call).and_return({ success: true, reconciled: 5, failed: 1 })

        expect {
          described_class.new.perform(entries: [ { error_type: "Boom" } ])
        }.not_to raise_error
      end
    end
  end
end
