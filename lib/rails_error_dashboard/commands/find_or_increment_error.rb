# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Find an existing error by hash or create a new one
    # Uses pessimistic locking to prevent race conditions in multi-app scenarios.
    #
    # Search order:
    # 1. Unresolved errors with same hash within 24 hours → increment occurrence count
    # 2. Resolved/wont_fix errors with same hash (any age) → reopen and increment
    # 3. No match → create new error record
    class FindOrIncrementError
      def self.call(error_hash, attributes = {})
        new(error_hash, attributes).call
      end

      def initialize(error_hash, attributes = {})
        @error_hash = error_hash
        @attributes = attributes
      end

      def call
        # Priority 1: Find unresolved match (existing behavior)
        existing = find_unresolved
        return increment_existing(existing) if existing

        # Priority 2: Find resolved/wont_fix match → reopen
        resolved = find_resolved
        return reopen_existing(resolved) if resolved

        # Priority 3: Create new record
        create_new_or_retry
      end

      private

      def find_unresolved
        ErrorLog.unresolved
          .where(error_hash: @error_hash)
          .where(application_id: @attributes[:application_id])
          .where("occurred_at >= ?", 24.hours.ago)
          .lock
          .order(last_seen_at: :desc)
          .first
      end

      def find_resolved
        ErrorLog
          .where(error_hash: @error_hash)
          .where(application_id: @attributes[:application_id])
          .where(status: %w[resolved wont_fix])
          .lock
          .order(last_seen_at: :desc)
          .first
      end

      def increment_existing(error)
        error.update!(
          occurrence_count: error.occurrence_count + 1,
          last_seen_at: Time.current,
          user_id: @attributes[:user_id] || error.user_id,
          request_url: @attributes[:request_url] || error.request_url,
          request_params: @attributes[:request_params] || error.request_params,
          user_agent: @attributes[:user_agent] || error.user_agent,
          ip_address: @attributes[:ip_address] || error.ip_address
        )
        error
      end

      def reopen_existing(error)
        attrs = {
          resolved: false,
          status: "new",
          resolved_at: nil,
          occurrence_count: error.occurrence_count + 1,
          last_seen_at: Time.current,
          user_id: @attributes[:user_id] || error.user_id,
          request_url: @attributes[:request_url] || error.request_url,
          request_params: @attributes[:request_params] || error.request_params,
          user_agent: @attributes[:user_agent] || error.user_agent,
          ip_address: @attributes[:ip_address] || error.ip_address
        }
        attrs[:reopened_at] = Time.current if ErrorLog.column_names.include?("reopened_at")
        error.update!(attrs)
        error.just_reopened = true
        error
      end

      def create_new_or_retry
        ErrorLog.create!(@attributes.reverse_merge(resolved: false))
      rescue ActiveRecord::RecordNotUnique
        # Race condition: another process created the same error
        retry_existing = ErrorLog.unresolved
          .where(error_hash: @error_hash)
          .where(application_id: @attributes[:application_id])
          .where("occurred_at >= ?", 24.hours.ago)
          .lock
          .first

        if retry_existing
          retry_existing.update!(
            occurrence_count: retry_existing.occurrence_count + 1,
            last_seen_at: Time.current
          )
          retry_existing
        else
          # Also check resolved in race condition path
          retry_resolved = ErrorLog
            .where(error_hash: @error_hash)
            .where(application_id: @attributes[:application_id])
            .where(status: %w[resolved wont_fix])
            .lock
            .first

          if retry_resolved
            reopen_existing(retry_resolved)
          else
            raise
          end
        end
      end
    end
  end
end
