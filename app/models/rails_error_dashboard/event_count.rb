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

    # Hour bucket a time belongs to, in UTC. One definition, used by both the
    # writer and the readers -- a mismatch here would silently split a bucket.
    # @param time [Time]
    # @return [Time]
    def self.bucket_for(time)
      (time || Time.current).utc.beginning_of_hour
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
    # @return [Boolean] true when the bucket was written
    def self.accumulate(error_log_id:, bucket_at:, count:)
      return false unless error_log_id && count.to_i.positive?
      return false unless table_exists?

      bucket = bucket_for(bucket_at)
      updated = where(error_log_id: error_log_id, bucket_at: bucket)
        .update_all([ "count = count + ?, updated_at = ?", count.to_i, Time.current ])
      return true if updated.positive?

      begin
        # requires_new: a failed INSERT aborts its transaction on PostgreSQL,
        # which would take the caller's surrounding transaction with it.
        transaction(requires_new: true) do
          create!(error_log_id: error_log_id, bucket_at: bucket, count: count.to_i)
        end
        true
      rescue ActiveRecord::RecordNotUnique
        # Another process created the same bucket between the UPDATE and the
        # INSERT. The row exists now, so the UPDATE that missed a moment ago
        # succeeds.
        where(error_log_id: error_log_id, bucket_at: bucket)
          .update_all([ "count = count + ?, updated_at = ?", count.to_i, Time.current ])
          .positive?
      end
    rescue StandardError => e
      # Never fail a storm flush over the rollup: the authoritative total is
      # still occurrence_count on the group. Losing a bucket degrades a time
      # window, it does not lose the count.
      RailsErrorDashboard::Logger.debug(
        "[RailsErrorDashboard] EventCount.accumulate failed: #{e.class} - #{e.message}"
      )
      false
    end

    def self.table_exists?
      connection.table_exists?(table_name)
    rescue StandardError
      false
    end
  end
end
