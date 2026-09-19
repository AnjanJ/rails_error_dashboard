# frozen_string_literal: true

module RailsErrorDashboard
  # How many storm-shed events landed on one error group in one hour.
  #
  # Storm protection sheds events by folding N of them into the group's
  # occurrence_count and writing no ErrorOccurrence row. That keeps the total
  # exact but leaves the events with no timestamp of their own, so a window
  # query has nothing to filter them by. This table gives them one.
  #
  # Window volume is therefore:
  #
  #   ErrorOccurrence rows in the window  +  EventCount buckets in the window
  #
  # Ordinary captures contribute the first term, shed events the second, and
  # neither is double counted: an event that wrote an occurrence row is never
  # also bucketed here.
  #
  # Inherits ErrorLogsRecord so separate-database routing applies.
  class EventCount < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_event_counts"

    belongs_to :error_log, class_name: "RailsErrorDashboard::ErrorLog", optional: true

    scope :in_window, ->(from, to = nil) {
      scope = where(arel_table[:bucket_at].gteq(from))
      to ? scope.where(arel_table[:bucket_at].lt(to)) : scope
    }

    # Bucket width, shared with the PRODUCER.
    #
    # This must equal CountBuffer::BUCKET_SECONDS, and there is a spec that
    # asserts it. The producer tallies 15-minute buckets precisely so that a
    # local midnight falls on a bucket EDGE in every UTC offset in use --
    # including +05:30 (Kolkata) and +05:45 (Kathmandu). Rounding those buckets
    # to the hour here destroyed exactly the property the producer paid for:
    # a storm event at 23:59:30 and one at 00:00:30 in Kolkata shared one
    # bucket, and a day's total was wrong by the whole straddle.
    BUCKET_SECONDS = Services::StormProtection::CountBuffer::BUCKET_SECONDS

    # The bucket a time belongs to, in UTC. One definition, used by the writer
    # and the readers -- a mismatch here silently splits or merges a bucket.
    # @param time [Time]
    # @return [Time]
    def self.bucket_for(time)
      time = (time || Time.current)
      Time.at((time.to_i / BUCKET_SECONDS) * BUCKET_SECONDS).utc
    end

    # Add +count+ shed events to (error_log_id, bucket_at), creating the row if
    # it is not there yet.
    #
    # Adapter-portable by hand rather than via upsert_all: the increment has to
    # read the existing value, and the ON CONFLICT / ON DUPLICATE KEY syntaxes
    # differ. The UPDATE-first shape means the common case (a storm flushing
    # repeatedly into the same hour) is a single statement, and the INSERT race
    # is resolved by retrying the UPDATE once.
    #
    # @return [Symbol] :written when the bucket landed, :unavailable when the
    #   rollup is permanently unusable (no table, bad args, an adapter that
    #   refuses the statement). A TRANSIENT failure raises instead.
    #
    #   Three states, not a boolean: the caller has to tell "the bucket is
    #   permanently unavailable, degrade" from "the write failed, retry the
    #   batch". Collapsing both into false made FlushStormCounts abort the
    #   whole transaction on a host that had simply never migrated the rollup
    #   table -- rolling back the authoritative lifetime count with it.
    def self.accumulate(error_log_id:, bucket_at:, count:)
      return :unavailable unless error_log_id && count.to_i.positive?
      return :unavailable unless table_exists?

      bucket = bucket_for(bucket_at)
      updated = where(error_log_id: error_log_id, bucket_at: bucket)
        .update_all([ "count = count + ?, updated_at = ?", count.to_i, Time.current ])
      return :written if updated.positive?

      begin
        # requires_new: a failed INSERT aborts its transaction on PostgreSQL,
        # which would take the caller's surrounding transaction with it.
        transaction(requires_new: true) do
          create!(error_log_id: error_log_id, bucket_at: bucket, count: count.to_i)
        end
        :written
      rescue ActiveRecord::RecordNotUnique
        # Another process created the same bucket between the UPDATE and the
        # INSERT. The row exists now, so the UPDATE that missed a moment ago
        # succeeds.
        where(error_log_id: error_log_id, bucket_at: bucket)
          .update_all([ "count = count + ?, updated_at = ?", count.to_i, Time.current ])
          .positive? ? :written : :unavailable
      end
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS => e
      # TRANSIENT: the store may be back in a moment. Do NOT swallow it.
      #
      # Returning false here let FlushStormCounts finalize its batch ledger
      # with the bucket missing, so the replay was suppressed as
      # already-applied and those events were erased from every time window --
      # permanently -- while the lifetime count stayed correct. The caller
      # turns this into an abort-and-retry of the whole batch.
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] EventCount.accumulate hit a transient failure: #{e.class} - #{e.message}"
      )
      raise
    rescue StandardError => e
      # PERMANENT: a malformed row, a missing table, an adapter that refuses
      # this statement. Retrying cannot help, and failing the flush would turn
      # a lost time bucket into a lost COUNT -- the authoritative total is
      # occurrence_count on the group, and it is already written.
      #
      # This is the only case the old comment actually described.
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] EventCount.accumulate failed permanently: #{e.class} - #{e.message}"
      )
      :unavailable
    end

    # Whether the rollup table is usable.
    #
    # A transient connection failure here is NOT "the table does not exist":
    # swallowing it returned false before any write was attempted, so a storm
    # flush reported success with no bucket written, and EventVolume silently
    # dropped the bucket term from its reads. Let the transient class through
    # so the caller can retry; only a genuinely absent table returns false.
    def self.table_exists?
      connection.table_exists?(table_name)
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS
      raise
    rescue StandardError
      false
    end
  end
end
