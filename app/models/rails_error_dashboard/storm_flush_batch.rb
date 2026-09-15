# frozen_string_literal: true

module RailsErrorDashboard
  # One row per storm count batch that has been reconciled onto ErrorLog rows.
  #
  # Storm counts are applied additively (occurrence_count + N), which is not
  # idempotent, so a replayed batch would count twice. The digest is inserted
  # in the same transaction as the increments: either both land or neither
  # does, and a replay violates the unique index instead of double-counting.
  #
  # Inherits ErrorLogsRecord so separate-database routing applies.
  class StormFlushBatch < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_storm_flush_batches"

    # The identity of a batch: which fingerprints, how many of each, the
    # overflow bucket, and the episode it belongs to.
    #
    # Sorted, so the same snapshot always digests to the same value whatever
    # order the entries arrive in. Counts are included, so a LATER batch for
    # the same fingerprints is a different identity and is applied normally --
    # only a genuine replay of the same counts is suppressed.
    #
    # @param entries [Array<Hash>] snapshot entries
    # @param overflow [Integer]
    # @param episode [Hash, nil]
    # @return [String] 64-character hex digest
    def self.digest_for(entries:, overflow: 0, episode: nil, batch_id: nil)
      # A batch id minted when the buffer was swapped identifies this batch
      # exactly: a retry carries the same one, and two separate batches never
      # share one. The content digest below is the fallback for a caller that
      # has none (an older in-flight job, or a direct call).
      return Digest::SHA256.hexdigest("batch:#{batch_id}") if batch_id.present?

      parts = Array(entries).map { |entry|
        entry = entry.with_indifferent_access if entry.respond_to?(:with_indifferent_access)
        next nil unless entry.is_a?(Hash)

        # gate_key identifies the fingerprint; opaque_identity is carried for
        # grouping and is included so two different errors that somehow shared
        # a gate_key could never collide here.
        [ entry["gate_key"], entry["opaque_identity"], entry["count"].to_i,
          entry["first_seen_at"], entry["last_seen_at"] ].join(":")
      }.compact.sort

      episode_part = episode.is_a?(Hash) ? episode["started_at"].to_s : ""

      Digest::SHA256.hexdigest([ parts.join("|"), overflow.to_i, episode_part ].join("#"))
    end
  end
end
