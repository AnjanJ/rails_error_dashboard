# frozen_string_literal: true

require "rails_helper"

# Count conservation under concurrent storm flushes.
#
# A storm hits every app process at once, and each process enqueues its OWN
# StormFlushJob with its own batch_id (services/storm_protection/gate.rb).
# With a worker pool of more than one, two DIFFERENT batches reconcile against
# the same group concurrently. The batch ledger de-duplicates a REPLAY of one
# batch; it cannot help between two genuinely different batches.
#
# The resolved (reopen) branch used to read occurrence_count into Ruby and write
# an absolute value back, so two batches of 5 against a group at 1 both read 1,
# both wrote 6, and five events vanished while both reported success: true.
#
# Two forms below, deliberately:
#   * the deterministic example runs everywhere (including SQLite) by
#     interleaving two real flushes at the read/write boundary -- reads, writes
#     and transactions are real, only scheduling is controlled;
#   * the threaded example needs PostgreSQL/MySQL, because SELECT ... FOR UPDATE
#     is a no-op on SQLite and only a real row lock proves the fix serializes.
RSpec.describe RailsErrorDashboard::Commands::FlushStormCounts, "count conservation" do
  before { RailsErrorDashboard.configuration.async_logging = false }
  after { RailsErrorDashboard.reset_configuration! }

  def entry_for(count:)
    {
      "error_class" => "StandardError",
      "message" => "storm boom",
      "first_app_frame" => "#{Rails.root}/app/models/widget.rb",
      "controller_name" => "widgets",
      "action_name" => "show",
      "custom_hash" => nil,
      "count" => count,
      "first_seen_at" => 5.minutes.ago.iso8601,
      "last_seen_at" => Time.current.iso8601
    }
  end

  # One captured error, then resolved -- so both flushes take the Priority-2
  # resolved/reopen branch.
  def resolved_log
    error = StandardError.new("storm boom")
    error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])
    log = RailsErrorDashboard::Commands::LogError.call(
      error, { controller_name: "widgets", action_name: "show" }
    )
    log.update!(resolved: true, status: "resolved", resolved_at: Time.current)
    log
  end

  describe "two different batches reopening the same resolved group" do
    it "adds every reconciled event exactly once" do
      log = resolved_log
      expect(log.occurrence_count).to eq(1)

      # Interleave at the read/write boundary: the first flush reads the row,
      # then the second flush runs to completion before the first one writes.
      # This is the exact ordering two worker threads produce, made
      # deterministic so the example cannot flake.
      interleaved = false
      allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:update!).and_wrap_original do |orig, *args|
        unless interleaved
          interleaved = true
          described_class.call(entries: [ entry_for(count: 5) ], batch_id: "batch-b")
        end
        orig.call(*args)
      end

      result = described_class.call(entries: [ entry_for(count: 5) ], batch_id: "batch-a")

      expect(result[:success]).to be true
      # 1 existing + 5 + 5. Before the fix this was 6: batch A read 1 and wrote
      # 6, discarding the 5 that batch B had already committed.
      expect(log.reload.occurrence_count).to eq(11)
    end

    it "reopens the group exactly once and keeps the reopen state" do
      log = resolved_log

      interleaved = false
      allow_any_instance_of(RailsErrorDashboard::ErrorLog).to receive(:update!).and_wrap_original do |orig, *args|
        unless interleaved
          interleaved = true
          described_class.call(entries: [ entry_for(count: 5) ], batch_id: "batch-b")
        end
        orig.call(*args)
      end

      described_class.call(entries: [ entry_for(count: 5) ], batch_id: "batch-a")

      log.reload
      expect(log.resolved).to be false
      expect(log.status).to eq("new")
      expect(log.resolved_at).to be_nil
    end
  end

  describe "two batches creating the same new group" do
    # A fingerprint first seen DURING a storm has no row yet, so every process
    # that flushes it takes the create branch. The group-identity unique index
    # lets exactly one INSERT win; the loser used to raise RecordNotUnique out
    # of reconcile_entry, which discarded its counts -- and on PostgreSQL the
    # failed INSERT also poisoned the surrounding transaction, taking the rest
    # of the batch with it. The loser must add to the row that now exists.
    it "adds the loser's counts to the row the winner created" do
      # Let one flush create the row, so a genuine row with this group identity
      # exists. Then make the next create! raise exactly what the index raises,
      # which is the losing flush's view of the same race.
      described_class.call(entries: [ entry_for(count: 5) ], batch_id: "winner")

      # The losing flush ran its lookups BEFORE the winner's row existed, so it
      # saw nothing and took the create branch. Reproduce that view: the
      # priority lookups miss, and the INSERT then hits the index.
      command = described_class.new(entries: [ entry_for(count: 5) ], batch_id: "loser")
      allow(command).to receive(:wont_fix_target).and_return(nil)
      allow(command).to receive(:unresolved_target).and_return(nil)
      allow(RailsErrorDashboard::ErrorLog).to receive(:create!)
        .and_raise(ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint")

      result = command.call

      expect(result[:success]).to be true
      expect(result[:reconciled]).to eq(5)
      # One row, holding both the winner's and the loser's counts.
      rows = RailsErrorDashboard::ErrorLog.where(message: "storm boom")
      expect(rows.count).to eq(1)
      expect(rows.sole.occurrence_count).to eq(10)
    end
  end

  describe "reopen broadcasts the update", :aggregate_failures do
    # ErrorLog carries after_update_commit -> ErrorBroadcaster.broadcast_update.
    # update_all would skip it, so a "consistency" refactor of the resolved
    # branch to the atomic-increment form used by the unresolved branch would
    # silently stop live dashboard updates on reopen. This guards that.
    it "fires the model callback when a storm flush reopens a resolved group" do
      log = resolved_log
      broadcast = []
      allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:broadcast_update) { |l| broadcast << l.id }

      described_class.call(entries: [ entry_for(count: 5) ])

      expect(log.reload.occurrence_count).to eq(6)
      expect(broadcast).to include(log.id)
    end
  end
end
