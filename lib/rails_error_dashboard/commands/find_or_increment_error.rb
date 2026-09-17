# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Find an existing error by hash or create a new one
    # Uses pessimistic locking to prevent race conditions in multi-app scenarios.
    # The whole find-and-write runs inside ONE transaction: a row lock taken
    # by SELECT ... FOR UPDATE lives only as long as the transaction that took
    # it, so a lock on a standalone SELECT was released before the UPDATE ran
    # and two concurrent captures could both read count N and both write N+1.
    #
    # Search order:
    # 0. wont_fix errors with same hash (any age) → increment, status untouched
    # 1. Unresolved errors with same hash within 24 hours → increment occurrence count
    # 2. Resolved errors with same hash (any age) → reopen and increment
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
        ErrorLog.transaction do
          # Priority 0: a wont_fix row absorbs its recurrences, at any age
          sticky = find_wont_fix
          next increment_existing(sticky) if sticky

          # Priority 1: Find unresolved match (existing behavior)
          existing = find_unresolved
          next increment_existing(existing) if existing

          # Priority 2: Find resolved match → reopen
          resolved = find_resolved
          next reopen_existing(resolved) if resolved

          # Priority 3: Create new record
          create_new_or_retry
        end
      end

      private

      # The three lookups are DISJOINT by status, so which row a recurrence
      # lands on never depends on the order they happen to run in.

      # "Won't fix" is a decision that the error recurs and will not be acted
      # on, so it has no time window: the row counts its recurrences for as
      # long as it keeps the status. It used to be matched by find_unresolved
      # for 24 hours and then REOPENED by find_resolved -- sticky for a day,
      # after which the triage decision was silently thrown away.
      def find_wont_fix
        with_environment(
          ErrorLog
            .where(error_hash: @error_hash)
            .where(application_id: @attributes[:application_id])
            .where(status: "wont_fix")
        ).lock.order(last_seen_at: :desc).first
      end

      def find_unresolved
        with_environment(
          not_wont_fix(ErrorLog.unresolved)
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
            .where(status: "resolved")
        ).lock.order(last_seen_at: :desc).first
      end

      # Spelled out rather than where.not(status: "wont_fix"): in SQL that also
      # drops every row whose status is NULL.
      def not_wont_fix(scope)
        scope.where("status IS NULL OR status <> ?", "wont_fix")
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

      # The request-identity fields the detail page shows beside the context
      # payloads. They are refreshed by the `||` chain in increment_existing,
      # so a capture can move the displayed URL without touching any
      # REFRESHED_CONTEXT key -- and the provenance has to follow the whole
      # displayed snapshot, not just part of it.
      REFRESHED_REQUEST_IDENTITY = %i[
        user_id request_url request_params user_agent ip_address
      ].freeze

      # Provenance for the snapshot the row will DISPLAY.
      #
      # Stamped whenever this occurrence refreshed ANY displayed field. An
      # occurrence that carried nothing (storm :lite, feature switched off)
      # leaves both the snapshot and its provenance alone -- otherwise the row
      # would claim a fresh capture time for evidence from an older event,
      # which is precisely the confusion this exists to remove.
      def context_provenance(refreshed)
        return {} unless refreshed.any? || refreshed_request_identity?
        return {} unless ErrorLog.column_names.include?("context_captured_at")

        provenance = { context_captured_at: @attributes[:occurred_at] || Time.current }
        if ErrorLog.column_names.include?("context_fidelity")
          provenance[:context_fidelity] = @attributes[:_context_fidelity].presence || "full"
        end
        provenance
      end

      def refreshed_request_identity?
        REFRESHED_REQUEST_IDENTITY.any? { |key| !@attributes[key].nil? }
      end

      # A group first seen during a storm has a MINIMAL exemplar: the flush job
      # could only record the first app frame, because a counted-only event
      # captures no backtrace. The comment there promises the next occurrence
      # fills in detail -- it never did, because nothing replaced backtrace on
      # an existing row, so the group kept a single bare path with no line
      # number or caller frame for its whole life.
      #
      # A capture that HAS a real backtrace now upgrades it. Only a full one:
      # a :lite capture sheds context by design and must not overwrite good
      # evidence with less.
      def backtrace_upgrade(error)
        return {} unless @attributes[:backtrace].present?
        return {} if storm_lite?

        stored = error.backtrace.to_s
        return {} if stored.include?("\n") # already a real stack

        incoming = @attributes[:backtrace].to_s
        return {} unless incoming.include?("\n") || incoming.length > stored.length

        upgrade = { backtrace: @attributes[:backtrace] }
        # The row is no longer a reconstructed exemplar: it now carries a real
        # stack from a real capture, so it must stop describing itself as
        # "minimal".
        if ErrorLog.column_names.include?("context_fidelity") && error.context_fidelity.to_s == "minimal"
          upgrade[:context_fidelity] = @attributes[:_context_fidelity].presence || "full"
        end
        upgrade
      end

      def storm_lite?
        @attributes[:_context_fidelity].to_s == "lite"
      end

      # {} unless this is a legacy NULL-environment row being claimed.
      def environment_adoption(error)
        return {} unless ErrorLog.column_names.include?("environment")
        return {} if error.environment.present? || @attributes[:environment].blank?

        { environment: @attributes[:environment] }
      end

      def increment_existing(error)
        refreshed = latest_context
        error.update!(
          occurrence_count: error.occurrence_count + 1,
          last_seen_at: Time.current,
          user_id: @attributes[:user_id] || error.user_id,
          request_url: @attributes[:request_url] || error.request_url,
          request_params: @attributes[:request_params] || error.request_params,
          user_agent: @attributes[:user_agent] || error.user_agent,
          ip_address: @attributes[:ip_address] || error.ip_address,
          **refreshed,
          **context_provenance(refreshed),
          **backtrace_upgrade(error),
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
          **(refreshed = latest_context),
          **context_provenance(refreshed),
          **backtrace_upgrade(error),
          **environment_adoption(error)
        }
        attrs[:reopened_at] = Time.current if ErrorLog.column_names.include?("reopened_at")
        error.update!(attrs)
        error.just_reopened = true
        error
      end

      # Attributes for a brand-new group.
      #
      # The first occurrence IS the snapshot, so its provenance is stamped here
      # rather than inferred later. Internal signalling keys (leading
      # underscore) are carriers between commands, not columns -- passing them
      # to create! raises UnknownAttributeError.
      def new_record_attributes
        attrs = @attributes.reject { |key, _| key.to_s.start_with?("_") }
        attrs = attrs.reverse_merge(resolved: false)

        if ErrorLog.column_names.include?("context_captured_at")
          attrs[:context_captured_at] ||= @attributes[:occurred_at] || Time.current
        end
        if ErrorLog.column_names.include?("context_fidelity")
          attrs[:context_fidelity] ||= @attributes[:_context_fidelity].presence || "full"
        end

        attrs
      end

      def create_new_or_retry
        # Savepoint: on PostgreSQL a unique-violation poisons the enclosing
        # transaction, and the retry lookups below would fail with "current
        # transaction is aborted" instead of finding the winner's row.
        ErrorLog.transaction(requires_new: true) do
          ErrorLog.create!(new_record_attributes)
        end
      rescue ActiveRecord::RecordNotUnique
        # Race condition: another process created the same error. Same three
        # lookups, same order, as the first pass.
        retry_sticky = find_wont_fix
        return increment_existing(retry_sticky) if retry_sticky

        retry_existing = with_environment(
          not_wont_fix(ErrorLog.unresolved)
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
              .where(status: "resolved")
          ).lock.first

          if retry_resolved
            reopen_existing(retry_resolved)
          else
            # A RecordNotUnique means a row with this exact group identity
            # exists right now, so the only way to get here is for the two
            # lookups above to disagree with the index: the colliding row sits
            # outside the 24 h window (its occurred_at was moved, or the clock
            # skewed) yet still holds this identity. Raising here would abort a
            # capture whose group demonstrably exists -- LogError's blanket
            # rescue turns that into a silently dropped error. Match the row
            # the index actually objected to and increment it instead.
            claim_conflicting_row || raise
          end
        end
      end

      # The unresolved row that owns this group identity, matched exactly as
      # the unique index defines it (application, hash, environment and the
      # immutable group_window bucket) with no time window of its own.
      def claim_conflicting_row
        return nil unless ErrorLog.column_names.include?("group_window")

        scope = ErrorLog.unresolved
          .where(error_hash: @error_hash)
          .where(application_id: @attributes[:application_id])
        scope = scope.where(environment: @attributes[:environment]) if ErrorLog.column_names.include?("environment")
        scope = scope.where(group_window: window_for_attributes)

        conflicting = scope.lock.first
        return nil unless conflicting

        conflicting.update!(
          occurrence_count: conflicting.occurrence_count + 1,
          last_seen_at: Time.current,
          **latest_context,
          **environment_adoption(conflicting)
        )
        conflicting
      end

      # The bucket this capture would have been stamped with -- the same value
      # ErrorLog#set_group_window computes.
      def window_for_attributes
        basis = @attributes[:occurred_at] || Time.current
        basis.utc.strftime("%Y-%m-%d")
      rescue StandardError
        nil
      end
    end
  end
end
