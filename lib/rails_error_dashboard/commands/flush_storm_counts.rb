# frozen_string_literal: true

module RailsErrorDashboard
  module Commands
    # Command: Reconcile counted-not-stored storm events onto ErrorLog rows
    # and maintain the storm_events episode record.
    #
    # Runs in a background job (DB allowed). For each counted fingerprint:
    #   1. Recompute the canonical error_hash from the stored identity parts
    #      (the gate's key deliberately omits application_id — resolved here)
    #   2. Unresolved match  → single UPDATE: occurrence_count += N
    #   3. Resolved match    → reopen (mirrors FindOrIncrementError semantics)
    #   4. No match          → create a minimal ErrorLog from the exemplar
    #
    # Counts are exact. Notifications are NOT dispatched from here — during a
    # storm they're suppressed by design; the storm notification covers it.
    class FlushStormCounts
      def self.call(entries:, overflow: 0, episode: nil)
        new(entries: entries, overflow: overflow, episode: episode).call
      end

      def initialize(entries:, overflow: 0, episode: nil)
        @entries = Array(entries)
        @overflow = overflow.to_i
        @episode = episode
      end

      def call
        application = resolve_application
        counted = 0

        @entries.each do |entry|
          entry = entry.with_indifferent_access if entry.respond_to?(:with_indifferent_access)
          counted += reconcile_entry(entry, application)
        rescue => e
          RailsErrorDashboard::Logger.error(
            "[RailsErrorDashboard] Storm count reconcile failed for #{entry["error_class"]}: #{e.class} - #{e.message}"
          )
        end

        upsert_storm_event(counted)
        { success: true, reconciled: counted, overflow: @overflow }
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] FlushStormCounts failed: #{e.class} - #{e.message}"
        )
        { success: false, error: "#{e.class}: #{e.message}" }
      end

      private

      def reconcile_entry(entry, application)
        count = entry["count"].to_i
        return 0 if count <= 0

        error_hash = canonical_hash(entry, application)
        last_seen = parse_time(entry["last_seen_at"]) || Time.current

        # Priority 1: unresolved match — one UPDATE, no row instantiation
        updated = ErrorLog.unresolved
          .where(error_hash: error_hash, application_id: application.id)
          .update_all([ "occurrence_count = occurrence_count + ?, last_seen_at = ?", count, last_seen ])
        return count if updated.positive?

        # Priority 2: resolved/wont_fix match — reopen, mirroring
        # FindOrIncrementError so storm recurrences don't stay buried
        resolved = ErrorLog
          .where(error_hash: error_hash, application_id: application.id)
          .where(status: %w[resolved wont_fix])
          .order(last_seen_at: :desc)
          .first
        if resolved
          attrs = {
            resolved: false,
            status: "new",
            resolved_at: nil,
            occurrence_count: resolved.occurrence_count + count,
            last_seen_at: last_seen
          }
          attrs[:reopened_at] = Time.current if ErrorLog.column_names.include?("reopened_at")
          resolved.update!(attrs)
          return count
        end

        # Priority 3: first seen during count-only mode — minimal ErrorLog
        # from the exemplar (no backtrace/context was captured; the next
        # occurrence after the storm fills in detail via the normal path)
        ErrorLog.create!(
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
        )
        count
      end

      # Mirrors ErrorHashGenerator.call exactly: same fields, same order,
      # same normalization — so counts land on the same ErrorLog the full
      # capture path would have used.
      def canonical_hash(entry, application)
        return entry["custom_hash"] if entry["custom_hash"].present?

        digest_input = [
          entry["error_class"],
          Services::ErrorHashGenerator.normalize_message(entry["message"]),
          entry["first_app_frame"],
          entry["controller_name"],
          entry["action_name"],
          application.id.to_s
        ].compact.join("|")

        Digest::SHA256.hexdigest(digest_input)[0..15]
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

        event.events_total = event.events_total.to_i + counted + @overflow
        event.events_counted_only = event.events_counted_only.to_i + counted
        event.events_overflow = event.events_overflow.to_i + @overflow
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
          { "class" => e["error_class"], "message" => e["message"].to_s[0, 120], "count" => e["count"].to_i }
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
