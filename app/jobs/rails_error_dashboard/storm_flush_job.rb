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

    def perform(entries: [], overflow: 0, episode: nil)
      entries = entries.map { |e| e.respond_to?(:stringify_keys) ? e.stringify_keys : e }
      episode = episode.stringify_keys if episode.respond_to?(:stringify_keys)

      result = Commands::FlushStormCounts.call(entries: entries, overflow: overflow, episode: episode)

      # A batch that reconciled nothing because every write failed is not a
      # delivered batch. Fail the job so Active Job retries it rather than
      # dropping counts that were only ever held in one process's memory.
      if result.is_a?(Hash) && result[:success] == false
        raise FlushFailed, "storm flush reconciled nothing: #{result[:error]}"
      end

      result
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS => e
      Rails.logger.error("[RailsErrorDashboard] StormFlushJob: error storage unavailable (#{e.class}: #{e.message}) — will retry")
      raise
    end
  end
end
