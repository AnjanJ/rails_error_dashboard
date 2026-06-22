# frozen_string_literal: true

module RailsErrorDashboard
  # Persists storm-protection count snapshots (mirrors SwallowedExceptionFlushJob):
  # the gate accumulates counts in memory with zero I/O, snapshots are handed
  # to this job at most once per flush interval, and ALL DB writes happen here.
  class StormFlushJob < ApplicationJob
    queue_as :default

    def perform(entries: [], overflow: 0, episode: nil)
      entries = entries.map { |e| e.respond_to?(:stringify_keys) ? e.stringify_keys : e }
      episode = episode.stringify_keys if episode.respond_to?(:stringify_keys)

      Commands::FlushStormCounts.call(entries: entries, overflow: overflow, episode: episode)
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] StormFlushJob failed: #{e.class} - #{e.message}")
    end
  end
end
