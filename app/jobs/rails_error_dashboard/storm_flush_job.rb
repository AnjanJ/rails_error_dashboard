# frozen_string_literal: true

module RailsErrorDashboard
  # Persists storm-protection count snapshots (mirrors SwallowedExceptionFlushJob):
  # the gate accumulates counts in memory with zero I/O, snapshots are handed
  # to this job at most once per flush interval, and ALL DB writes happen here.
  class StormFlushJob < ApplicationJob
    # Raised when the command reports that nothing in the batch could be
    # written, so retry_on can schedule another attempt.
    class FlushFailed < StandardError; end

    queue_as :default

    def perform(entries: [], overflow: 0, episode: nil, batch_id: nil)
      entries = entries.map { |e| e.respond_to?(:stringify_keys) ? e.stringify_keys : e }
      episode = episode.stringify_keys if episode.respond_to?(:stringify_keys)

      # batch_id identifies THIS batch across retries: ApplicationJob replays
      # the identical payload, and the ledger has to recognise it.
      result = Commands::FlushStormCounts.call(
        entries: entries, overflow: overflow, episode: episode, batch_id: batch_id
      )

      # A batch that wrote nothing is not a delivered batch. Fail the job so
      # Active Job retries it rather than dropping counts that were only ever
      # held in one process's memory. Two shapes reach here: every entry failed
      # permanently, and a transient store failure that rolled the whole batch
      # back (retryable: true) -- the latter is intact and safe to replay.
      if result.is_a?(Hash) && result[:success] == false
        reason = result[:retryable] ? "storm flush rolled back" : "storm flush reconciled nothing"
        raise FlushFailed, "#{reason}: #{result[:error]}"
      end

      result
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS => e
      Rails.logger.error("[RailsErrorDashboard] StormFlushJob: error storage unavailable (#{e.class}: #{e.message}) — will retry")
      raise
    end
  end
end
