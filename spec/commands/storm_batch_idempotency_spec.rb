# frozen_string_literal: true

require "rails_helper"

# Storm counts are applied additively (occurrence_count + N), which is not
# idempotent: delivering the same snapshot twice counted it twice.
#
# The realistic replay is the job's own retry. StormFlushJob raises when a
# batch reconciles nothing, and ApplicationJob retries three times with the
# identical payload; a queue that redelivers does the same. A digest of the
# batch is therefore inserted in the SAME transaction as the increments, so
# either both land or neither does, and a replay hits the unique index.
RSpec.describe "storm batch idempotency" do
  let(:flush) { RailsErrorDashboard::Commands::FlushStormCounts }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:ledger) { RailsErrorDashboard::StormFlushBatch }

  before do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard.configuration.enable_storm_protection = true
    RailsErrorDashboard.configuration.async_logging = false
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  # One clock reading per example. entry is called once per "delivery", and the
  # batch digest covers last_seen_at: reading the clock inside entry meant that
  # a second boundary between two calls turned the SAME batch into a different
  # one, and the redelivery examples failed intermittently.
  let(:now) { Time.current.change(usec: 0) }

  def entry(count: 5, gate_key: "gk-1", message: "storm boom")
    {
      "gate_key" => gate_key,
      "error_class" => "StandardError",
      "message" => message,
      "first_app_frame" => "#{Rails.root}/app/models/widget.rb",
      "count" => count,
      "first_seen_at" => (now - 5.minutes).iso8601,
      "last_seen_at" => now.iso8601
    }
  end

  it "applies a batch exactly once when it is delivered twice" do
    first = flush.call(entries: [ entry ])
    second = flush.call(entries: [ entry ])

    expect(first).to include(success: true, reconciled: 5)
    expect(second).to include(success: true, reconciled: 0, already_applied: true)
    expect(logs.sum(:occurrence_count)).to eq(5)
    expect(ledger.count).to eq(1)
  end

  # The digest covers the counts, not just the fingerprints, so a LATER batch
  # for the same error is a different identity and must still be applied.
  it "does not suppress a different batch" do
    flush.call(entries: [ entry(count: 5) ])
    flush.call(entries: [ entry(count: 3) ])
    flush.call(entries: [ entry(count: 5, gate_key: "gk-2", message: "other boom") ])

    expect(logs.sum(:occurrence_count)).to eq(13)
    expect(ledger.count).to eq(3)
  end

  # Claiming a batch that then wrote nothing would make the failure
  # permanent -- the retry would be suppressed as a replay and the counts
  # would be lost for good. Worse than double counting.
  it "rolls the claim back when nothing could be written, so the retry works" do
    allow(logs).to receive(:unresolved).and_raise(ActiveRecord::ConnectionNotEstablished, "store down")

    failed = flush.call(entries: [ entry ])

    expect(failed[:success]).to be false
    expect(ledger.count).to eq(0)

    allow(logs).to receive(:unresolved).and_call_original

    retried = flush.call(entries: [ entry ])

    expect(retried).to include(success: true, reconciled: 5)
    expect(logs.sum(:occurrence_count)).to eq(5)
  end

  it "records what the batch applied, for an operator reading the ledger" do
    flush.call(entries: [ entry(count: 7), entry(count: 2, gate_key: "gk-2", message: "second") ])

    row = ledger.sole
    expect(row.entry_count).to eq(2)
    expect(row.occurrences_applied).to eq(9)
    expect(row.applied_at).to be_present
  end

  # A content digest alone cannot tell two SEPARATE batches apart when they
  # carry identical counts for the same fingerprints inside one second
  # (snapshot timestamps are second-granular). The second would be dropped as
  # a replay, losing real counts. CountBuffer#snapshot! therefore mints an id
  # for each swap of the buffer: every entry in that batch left the buffer in
  # that swap and appears in no other batch, while a retry carries the id
  # unchanged.
  describe "batch identity" do
    it "applies two separate batches that happen to carry identical counts" do
      first = flush.call(entries: [ entry ], batch_id: SecureRandom.uuid)
      second = flush.call(entries: [ entry ], batch_id: SecureRandom.uuid)

      expect(first).to include(reconciled: 5)
      expect(second).to include(reconciled: 5)
      expect(logs.sum(:occurrence_count)).to eq(10)
    end

    it "suppresses a replay of the same batch id" do
      batch_id = SecureRandom.uuid

      flush.call(entries: [ entry ], batch_id: batch_id)
      replay = flush.call(entries: [ entry ], batch_id: batch_id)

      expect(replay).to include(reconciled: 0, already_applied: true)
      expect(logs.sum(:occurrence_count)).to eq(5)
    end

    it "mints a distinct id for every swap of the buffer" do
      buffer = RailsErrorDashboard::Services::StormProtection::CountBuffer.new
      parts = { error_class: "StandardError", message: "boom", first_app_frame: "/app/w.rb" }

      buffer.record("k", parts)
      first = buffer.snapshot!
      buffer.record("k", parts)
      second = buffer.snapshot!

      expect(first[:batch_id]).to be_present
      expect(second[:batch_id]).not_to eq(first[:batch_id])
    end
  end

  # A host upgrades the gem before it runs the migration. The ledger is a
  # safety net, not a gate: counts exist nowhere else, so reconcile anyway.
  it "reconciles normally when the ledger table has not been migrated yet" do
    allow(ledger).to receive(:table_exists?).and_return(false)

    result = flush.call(entries: [ entry ])

    expect(result).to include(success: true, reconciled: 5)
    expect(logs.sum(:occurrence_count)).to eq(5)
  end
end
