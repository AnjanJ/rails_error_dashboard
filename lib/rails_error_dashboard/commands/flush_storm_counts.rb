# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Reconcile counted-not-stored storm events onto ErrorLog rows
    # and maintain the storm_events episode record.
    #
    # Runs in a background job (DB allowed). For each counted fingerprint:
    #   1. Recompute the canonical error_hash from the stored identity parts
    #      (the gate's key deliberately omits application_id — resolved here)
    #   2. Unresolved match  → the ONE row FindOrIncrementError would pick
    #      (24 h window, exact environment first): occurrence_count += N
    #   3. Resolved match    → reopen (mirrors FindOrIncrementError semantics)
    #   4. No match          → create a minimal ErrorLog from the exemplar
    #
    # Counts are exact. Notifications are NOT dispatched from here — during a
    # storm they're suppressed by design; the storm notification covers it.
    class FlushStormCounts
      def self.call(entries:, overflow: 0, episode: nil, batch_id: nil)
        new(entries: entries, overflow: overflow, episode: episode, batch_id: batch_id).call
      end

      def initialize(entries:, overflow: 0, episode: nil, batch_id: nil)
        # The gate scrubs what it buffers, so this is normally a no-op scan. It
        # covers entries buffered by an older release and direct callers: the
        # exemplar becomes an ErrorLog row, and its message is matched by regex.
        @entries = Array(Services::EncodingSanitizer.scrub_deep(entries))
        @overflow = overflow.to_i
        @episode = episode
        @batch_id = batch_id
      end

      def call
        application = resolve_application
        counted = 0
        failed = 0
        aborted = false

        # Counts are applied additively (occurrence_count + N), which is not
        # idempotent: delivering the same snapshot twice counted it twice. The
        # realistic replay is this job's own retry -- StormFlushJob raises when
        # a batch reconciles nothing, and ApplicationJob retries it three times
        # with the identical payload -- and a queue that redelivers does the
        # same.
        #
        # The batch digest is inserted in the SAME transaction as the
        # increments, so either both land or neither does. A replay violates
        # the unique index and is reported as already applied rather than
        # counted again.
        ledger = batch_ledger_entry
        return already_applied_result if ledger == :already_applied

        ErrorLog.transaction do
          claim_batch!(ledger)

          @entries.each do |entry|
            entry = entry.with_indifferent_access if entry.respond_to?(:with_indifferent_access)
            counted += reconcile_entry(entry, application)
          rescue *Commands::LogError::RETRYABLE_STORE_ERRORS => e
            # A transient store failure is NOT a bad entry. Claiming the batch
            # here would commit the ledger row and strand every entry not yet
            # applied: the retry is then suppressed as a replay and those events
            # are lost for good. Re-raise so the whole transaction rolls back --
            # nothing was committed, so nothing can double -- and let the job
            # retry the batch intact. The generic rescue below still keeps a
            # permanently malformed entry from poisoning its batch.
            failed += 1
            aborted = true
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] Storm batch aborted by a transient store failure: #{e.class} - #{e.message}"
            )
            raise
          rescue => e
            # A corrupt (non-Hash) entry must not abort the whole batch — and the
            # log line itself must not assume `entry` is subscriptable (an Integer
            # from a broken serializer would raise again here, escaping this rescue).
            failed += 1
            error_class = entry.is_a?(Hash) ? entry["error_class"] : entry.class
            RailsErrorDashboard::Logger.error(
              "[RailsErrorDashboard] Storm count reconcile failed for #{error_class}: #{e.class} - #{e.message}"
            )
          end

          # Nothing was written, so there is nothing to protect from a replay:
          # roll the claim back and let the job retry the whole batch.
          raise ActiveRecord::Rollback if failed.positive? && counted.zero?

          finalize_batch!(ledger, counted)
        end

        # Every entry failed and none was written. Reporting success with
        # reconciled: 0 made a total loss indistinguishable from an empty
        # batch, so the job acknowledged counts that never reached the
        # database.
        #
        # Reaching here means every failure was PERMANENT -- a transient store
        # failure re-raises above and rolls the whole batch back. Partial
        # success over permanent failures stays successful: the entries that
        # were written are written, replaying would double them, and retrying a
        # corrupt payload only loops forever.
        if failed.positive? && counted.zero?
          return { success: false, retryable: false, reconciled: 0, failed: failed, overflow: @overflow,
                   error: "all #{failed} entries failed to reconcile" }
        end

        upsert_storm_event(counted)
        { success: true, reconciled: counted, failed: failed, overflow: @overflow }
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] FlushStormCounts failed: #{e.class} - #{e.message}"
        )
        # retryable: true says "the batch is intact, replay it" -- nothing was
        # committed, so the job can retry without doubling. A permanent failure
        # carries no such promise.
        retryable = Commands::LogError::RETRYABLE_STORE_ERRORS.any? { |klass| e.is_a?(klass) }
        result = { success: false, retryable: retryable, error: "#{e.class}: #{e.message}" }
        # reconciled: 0 because the transaction rolled back -- whatever this
        # batch had counted in memory never reached the database.
        result.merge!(reconciled: 0, failed: failed, overflow: @overflow) if aborted
        result
      end

      private

      # nil when the ledger is unavailable (table not migrated yet -- the
      # command then behaves exactly as it did before), :already_applied when
      # this exact batch is already recorded, otherwise the digest to claim.
      def batch_ledger_entry
        return nil unless ledger_available?

        digest = StormFlushBatch.digest_for(
          entries: @entries, overflow: @overflow, episode: @episode, batch_id: @batch_id
        )
        return :already_applied if StormFlushBatch.exists?(digest: digest)

        digest
      rescue => e
        # The ledger is a safety net, not a gate: if it cannot be consulted,
        # reconcile anyway rather than dropping counts that exist nowhere else.
        RailsErrorDashboard::Logger.debug(
          "[RailsErrorDashboard] Storm batch ledger unavailable: #{e.class} - #{e.message}"
        )
        nil
      end

      def claim_batch!(digest)
        return unless digest.is_a?(String)

        StormFlushBatch.create!(
          digest: digest,
          entry_count: @entries.size,
          occurrences_applied: 0,
          applied_at: Time.current
        )
      end

      # Record what the batch actually applied, for an operator reading the
      # ledger. The row already exists; this only fills in the total.
      def finalize_batch!(digest, counted)
        return unless digest.is_a?(String)

        StormFlushBatch.where(digest: digest).update_all(occurrences_applied: counted)
      end

      def already_applied_result
        RailsErrorDashboard::Logger.info(
          "[RailsErrorDashboard] Storm flush batch already applied — skipping replay"
        )
        { success: true, reconciled: 0, failed: 0, overflow: @overflow, already_applied: true }
      end

      def ledger_available?
        defined?(StormFlushBatch) && StormFlushBatch.table_exists?
      rescue StandardError
        false
      end


      def reconcile_entry(entry, application)
        count = entry["count"].to_i
        return 0 if count <= 0

        error_hash = canonical_hash(entry, application)
        last_seen = parse_time(entry["last_seen_at"]) || Time.current
        # An explicit environment captured at the gate wins over the worker's
        # own, mirroring LogError#resolve_environment for full captures.
        env = current_environment && (entry["environment"].presence || current_environment)

        # Priority 1: unresolved match — ONE row, chosen exactly as
        # FindOrIncrementError chooses it (same hash + application, occurred
        # within 24 h, exact environment before a legacy NULL row, most
        # recently seen first), then a single atomic UPDATE on that id.
        #
        # It must be one row: the normal path opens a fresh group once the
        # previous one's occurred_at falls outside the 24 h window, so a
        # long-running unresolved error legitimately owns several unresolved
        # rows. An update_all across the whole hash would add N to every one
        # of them — seven real events becoming twelve counted occurrences.
        #
        # Priority 0, tried first: a wont_fix row absorbs its recurrences at any
        # age and keeps its status (FindOrIncrementError#find_wont_fix). Same
        # atomic increment, so it shares the branch below.
        target = wont_fix_target(error_hash, application, env) ||
                 unresolved_target(error_hash, application, env)
        if target
          if env && target.environment.blank?
            ErrorLog.where(id: target.id).update_all([
              "occurrence_count = occurrence_count + ?, last_seen_at = ?, environment = ?",
              count, last_seen, env
            ])
          else
            ErrorLog.where(id: target.id).update_all([
              "occurrence_count = occurrence_count + ?, last_seen_at = ?", count, last_seen
            ])
          end
          return count
        end

        # Priority 2: resolved match — reopen, mirroring
        # FindOrIncrementError so storm recurrences don't stay buried
        resolved_scope = ErrorLog
          .where(error_hash: error_hash, application_id: application.id)
          .where(status: "resolved")
        if env
          resolved_scope = resolved_scope.where(environment: [ env, nil ])
            .order(Arel.sql("CASE WHEN environment IS NULL THEN 1 ELSE 0 END"))
        end
        # .lock (SELECT ... FOR UPDATE) held to commit by the transaction opened
        # in #call, exactly as FindOrIncrementError does for the same reopen.
        # Without it this branch read occurrence_count into Ruby and wrote an
        # ABSOLUTE value back, so two concurrent batches both read N and both
        # wrote N+count -- one batch's events vanished while both reported
        # success. The unresolved branch above is safe because it increments in
        # SQL; this branch cannot use update_all because reopening is a state
        # transition the dashboard must see, and update_all skips the
        # after_update_commit broadcast.
        resolved = resolved_scope.lock.order(last_seen_at: :desc).first
        if resolved
          # The count is incremented in SQL, never read into Ruby and written
          # back. This branch used to compute `resolved.occurrence_count + count`
          # and write that ABSOLUTE value, so two concurrent batches both read N
          # and both wrote N+count -- one batch's events vanished while both
          # reported success. The .lock above serializes the pair on
          # PostgreSQL/MySQL; the atomic increment below conserves the count on
          # every adapter, including SQLite where FOR UPDATE is a no-op.
          ErrorLog.where(id: resolved.id).update_all([
            "occurrence_count = occurrence_count + ?", count
          ])

          # The reopen is a state transition the dashboard must see, so it stays
          # an update! -- update_all would skip the after_update_commit
          # broadcast. Reload first so this write does not clobber the increment
          # just made with a stale in-memory occurrence_count.
          resolved.reload
          attrs = {
            resolved: false,
            status: "new",
            resolved_at: nil,
            last_seen_at: last_seen
          }
          attrs[:reopened_at] = Time.current if ErrorLog.column_names.include?("reopened_at")
          attrs[:environment] = env if env && resolved.environment.blank?
          resolved.update!(attrs)
          return count
        end

        # Priority 3: first seen during count-only mode — minimal ErrorLog
        # from the exemplar (no backtrace/context was captured; the next
        # occurrence after the storm fills in detail via the normal path).
        #
        # The exemplar message arrives ALREADY REDACTED: the gate filters it
        # before buffering, because the buffer is shipped to StormFlushJob over
        # a durable queue. Grouping does not depend on the raw text -- the gate
        # hashed the identity from it and sent the digest along
        # (opaque_identity) -- so this row still lands where the full capture
        # path would put it. The filter below stays as a second line of
        # defence for entries from an older release still in flight.
        create_attrs = {
          environment: env,
          application_id: application.id,
          error_type: entry["error_class"],
          message: entry["message"],
          backtrace: entry["first_app_frame"],
          controller_name: entry["controller_name"],
          action_name: entry["action_name"],
          occurred_at: parse_time(entry["first_seen_at"]) || Time.current,
          last_seen_at: last_seen,
          occurrence_count: count,
          error_hash: error_hash,
          resolved: false
        }.compact

        # This row is reconstructed from a counted-only exemplar: there is no
        # backtrace beyond the first app frame and no context at all. Saying so
        # is what lets the dashboard distinguish "nothing was captured" from
        # "nothing happened", and what lets the next full capture upgrade the
        # backtrace instead of leaving a bare path forever.
        if ErrorLog.column_names.include?("context_fidelity")
          create_attrs[:context_fidelity] = "minimal"
        end
        if ErrorLog.column_names.include?("context_captured_at")
          create_attrs[:context_captured_at] = create_attrs[:occurred_at]
        end
        begin
          # requires_new opens a SAVEPOINT: on PostgreSQL a failed INSERT aborts
          # its transaction, and every later statement -- including the recovery
          # lookup below -- fails with InFailedSqlTransaction. The savepoint
          # confines the damage to this INSERT so the batch can continue.
          ErrorLog.transaction(requires_new: true) do
            ErrorLog.create!(**ErrorLog.clamp_string_attributes(Services::SensitiveDataFilter.filter_attributes(create_attrs)))
          end
        rescue ActiveRecord::RecordNotUnique
          # Another flush created this group between our lookups and this
          # INSERT -- the group-identity index objected. Two concurrent batches
          # for the same fingerprint is the NORMAL storm shape (every process
          # flushes its own batch), so this must not fail the entry: the counts
          # exist nowhere but in this payload. Re-run the same lookups and add
          # to the row that now exists, exactly as FindOrIncrementError does.
          #
          # Nested in its own transaction because the failed INSERT poisons the
          # surrounding one on PostgreSQL.
          raise unless (target = existing_target(error_hash, application, env))

          ErrorLog.where(id: target.id).update_all([
            "occurrence_count = occurrence_count + ?, last_seen_at = ?", count, last_seen
          ])
        end
        count
      end

      # The row a retried INSERT should add to: any row holding this group
      # identity, whatever its status. Deliberately wider than the
      # priority-ordered lookups above -- the index has already proved a row
      # with this identity exists, so refusing to match a resolved or wont_fix
      # one would drop the counts instead.
      def existing_target(error_hash, application, env)
        scope = ErrorLog.where(error_hash: error_hash, application_id: application.id)
        scope = scope.where(environment: [ env, nil ]) if env
        scope.order(last_seen_at: :desc).select(:id).first
      end

      # The unresolved row the full capture path would increment right now.
      # No time window: "won't fix" holds for as long as the row keeps the status.
      def wont_fix_target(error_hash, application, env)
        scope = ErrorLog
          .where(error_hash: error_hash, application_id: application.id)
          .where(status: "wont_fix")
        if env
          scope = scope.where(environment: [ env, nil ])
            .order(Arel.sql("CASE WHEN environment IS NULL THEN 1 ELSE 0 END"))
        end
        scope.order(last_seen_at: :desc).select(:id, :environment).first
      end

      def unresolved_target(error_hash, application, env)
        # Disjoint from wont_fix_target. Not where.not(...): that would also
        # drop rows whose status is NULL.
        scope = ErrorLog.unresolved
          .where("status IS NULL OR status <> ?", "wont_fix")
          .where(error_hash: error_hash, application_id: application.id)
          .where("occurred_at >= ?", 24.hours.ago)
        if env
          scope = scope.where(environment: [ env, nil ])
            .order(Arel.sql("CASE WHEN environment IS NULL THEN 1 ELSE 0 END"))
        end
        scope.order(last_seen_at: :desc).select(:id, :environment).first
      end

      # The redaction LogError applies to a message, for exemplars that reach
      # the database by any other route (first-seen rows, the storm ledger).
      def redact_message(message)
        return message if message.blank?

        Services::SensitiveDataFilter.filter_attributes({ message: message.to_s })[:message]
      end

      # Finishes the same two-stage fingerprint the full capture path uses, so
      # counts land on the ErrorLog that path would have chosen.
      def canonical_hash(entry, application)
        return entry["custom_hash"] if entry["custom_hash"].present?

        # The gate hashed the identity from the RAW message and buffered only
        # the digest; the buffered "message" is redacted, so recomputing from
        # it here would produce a DIFFERENT fingerprint and storm counts would
        # land on a different row than the full capture path.
        opaque = entry["opaque_identity"].presence || Services::ErrorHashGenerator.opaque_identity(
          error_class: entry["error_class"],
          normalized_message: Services::ErrorHashGenerator.normalize_message(entry["message"]),
          frames: entry["first_app_frame"],
          controller_name: entry["controller_name"],
          action_name: entry["action_name"]
        )

        Services::ErrorHashGenerator.complete(opaque, application.id)
      end

      # nil when the column is not migrated yet, so every environment clause
      # above disappears and the command behaves exactly as before.
      def current_environment
        return nil unless ErrorLog.column_names.include?("environment")

        RailsErrorDashboard.configuration.current_environment
      end

      def resolve_application
        # Same chain LogError uses — app name is process-global
        app_name = RailsErrorDashboard.configuration.application_name ||
                   ENV["APPLICATION_NAME"] ||
                   (defined?(Rails) && Rails.application.class.module_parent_name) ||
                   "Rails Application"
        Application.find_or_create_by_name(app_name)
      end

      def upsert_storm_event(counted)
        return unless @episode.is_a?(Hash)
        return unless StormEvent.table_exists?

        started_at = parse_time(@episode["started_at"])
        return unless started_at

        event = StormEvent.active.recent_first.first || StormEvent.create!(started_at: started_at)

        event.events_counted_only = event.events_counted_only.to_i + counted
        event.events_overflow = event.events_overflow.to_i + @overflow
        # events_total is the count-only total: in-map reconciled + overflow.
        # It deliberately excludes :lite/:full admissions (those became real
        # ErrorLog rows on the hot path and are never counted here), so it is
        # always events_counted_only + events_overflow. Derive it rather than
        # accumulate so it can't drift from its two components.
        event.events_total = event.events_counted_only.to_i + event.events_overflow.to_i
        event.fingerprints_affected = [ event.fingerprints_affected.to_i, @entries.size ].max
        event.peak_rate_per_minute = [ event.peak_rate_per_minute.to_i, @episode["peak_rate_per_minute"].to_i ].max
        event.reached_open ||= @episode["reached_open"] == true
        event.top_fingerprints = top_fingerprints_json(event)
        event.ended_at = parse_time(@episode["ended_at"]) if @episode["ended_at"]
        event.save!
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] Storm event upsert failed: #{e.class} - #{e.message}"
        )
      end

      def top_fingerprints_json(event)
        existing = event.top_fingerprints_list
        fresh = @entries.map { |e|
          e = e.with_indifferent_access if e.respond_to?(:with_indifferent_access)
          { "class" => e["error_class"], "message" => redact_message(e["message"]).to_s[0, 120], "count" => e["count"].to_i }
        }

        merged = (existing + fresh)
          .group_by { |f| [ f["class"], f["message"] ] }
          .map { |_k, group| group.first.merge("count" => group.sum { |f| f["count"].to_i }) }

        merged.sort_by { |f| -f["count"].to_i }.first(5).to_json
      end

      def parse_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
