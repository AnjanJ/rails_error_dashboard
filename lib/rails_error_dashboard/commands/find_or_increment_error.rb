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
    #
    # Environment is a MATCH dimension, not part of the hash: the same error in
    # staging and production is two rows with independent status. A row with a
    # NULL environment predates the column; it matches as a wildcard and is
    # stamped by the first occurrence that claims it, so history migrates
    # itself without a backfill. An exact match always wins over a NULL one.
    class FindOrIncrementError
      # Context that describes THIS occurrence rather than the error as a
      # group. It is refreshed on every recurrence so the row always shows the
      # latest moment of failure, not the first one in the 24 h window. Keys
      # absent from @attributes (feature disabled, column not migrated, or a
      # storm :lite capture that shed context) leave the stored payload alone —
      # a shed capture must never blank out a good snapshot.
      REFRESHED_CONTEXT = %i[
        breadcrumbs system_health local_variables instance_variables
        http_method hostname content_type request_duration_ms
      ].freeze

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
        with_environment(
          ErrorLog.unresolved
            .where(error_hash: @error_hash)
            .where(application_id: @attributes[:application_id])
            .where("occurred_at >= ?", 24.hours.ago)
        ).lock.order(last_seen_at: :desc).first
      end

      def find_resolved
        with_environment(
          ErrorLog
            .where(error_hash: @error_hash)
            .where(application_id: @attributes[:application_id])
            .where(status: %w[resolved wont_fix])
        ).lock.order(last_seen_at: :desc).first
      end

      # Restrict to this occurrence's environment or a legacy NULL row, exact
      # first. Literal SQL, no interpolation. A blank environment (column not
      # migrated yet, or an attribute-less caller) leaves the scope unchanged.
      def with_environment(scope)
        env = @attributes[:environment]
        return scope if env.blank? || !ErrorLog.column_names.include?("environment")

        scope.where(environment: [ env, nil ])
             .order(Arel.sql("CASE WHEN environment IS NULL THEN 1 ELSE 0 END"))
      end

      # The subset of REFRESHED_CONTEXT this occurrence actually captured.
      def latest_context
        REFRESHED_CONTEXT.each_with_object({}) do |key, refreshed|
          refreshed[key] = @attributes[key] unless @attributes[key].nil?
        end
      end

      # {} unless this is a legacy NULL-environment row being claimed.
      def environment_adoption(error)
        return {} unless ErrorLog.column_names.include?("environment")
        return {} if error.environment.present? || @attributes[:environment].blank?

        { environment: @attributes[:environment] }
      end

      def increment_existing(error)
        error.update!(
          occurrence_count: error.occurrence_count + 1,
          last_seen_at: Time.current,
          user_id: @attributes[:user_id] || error.user_id,
          request_url: @attributes[:request_url] || error.request_url,
          request_params: @attributes[:request_params] || error.request_params,
          user_agent: @attributes[:user_agent] || error.user_agent,
          ip_address: @attributes[:ip_address] || error.ip_address,
          **latest_context,
          **environment_adoption(error)
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
          ip_address: @attributes[:ip_address] || error.ip_address,
          **latest_context,
          **environment_adoption(error)
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
        retry_existing = with_environment(
          ErrorLog.unresolved
            .where(error_hash: @error_hash)
            .where(application_id: @attributes[:application_id])
            .where("occurred_at >= ?", 24.hours.ago)
        ).lock.first

        if retry_existing
          retry_existing.update!(
            occurrence_count: retry_existing.occurrence_count + 1,
            last_seen_at: Time.current,
            **latest_context,
            **environment_adoption(retry_existing)
          )
          retry_existing
        else
          # Also check resolved in race condition path
          retry_resolved = with_environment(
            ErrorLog
              .where(error_hash: @error_hash)
              .where(application_id: @attributes[:application_id])
              .where(status: %w[resolved wont_fix])
          ).lock.first

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
