# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Find an existing error by hash or create a new one
    # Uses pessimistic locking to prevent race conditions in multi-app scenarios.
    # If an unresolved error with the same hash exists within 24 hours, increments
    # its occurrence count. Otherwise creates a new error record.
    class FindOrIncrementError
      def self.call(error_hash, attributes = {})
        new(error_hash, attributes).call
      end

      def initialize(error_hash, attributes = {})
        @error_hash = error_hash
        @attributes = attributes
      end

      def call
        existing = find_existing

        if existing
          increment_existing(existing)
        else
          create_new_or_retry
        end
      end

      private

      def find_existing
        ErrorLog.unresolved
          .where(error_hash: @error_hash)
          .where(application_id: @attributes[:application_id])
          .where("occurred_at >= ?", 24.hours.ago)
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

      def create_new_or_retry
        ErrorLog.create!(@attributes.reverse_merge(resolved: false))
      rescue ActiveRecord::RecordNotUnique
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
          raise
        end
      end
    end
  end
end
