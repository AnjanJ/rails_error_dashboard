# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure service: Detect N+1 query patterns from SQL breadcrumbs
    #
    # Analyzes already-captured breadcrumbs at display time (NOT on every request).
    # Groups SQL queries by normalized fingerprint and flags patterns where the
    # same query shape appears >= threshold times.
    #
    # SAFETY: O(n) over max 40 breadcrumbs, wrapped in rescue => [].
    class NplusOneDetector
      class << self
        # Detect N+1 patterns in breadcrumbs
        # @param breadcrumbs [Array<Hash>] Parsed breadcrumb array from JSON
        # @param threshold [Integer, nil] Minimum repetitions to flag (default: config or 3)
        # @return [Array<Hash>] Detected patterns sorted by count desc
        def call(breadcrumbs, threshold: nil)
          return [] unless breadcrumbs.is_a?(Array) && breadcrumbs.any?

          threshold ||= RailsErrorDashboard.configuration.n_plus_one_threshold || 3

          # Extract SQL breadcrumbs only
          sql_crumbs = breadcrumbs.select { |c| c["c"] == "sql" }
          return [] if sql_crumbs.empty?

          # Group by normalized fingerprint
          groups = Hash.new { |h, k| h[k] = { count: 0, total_duration_ms: 0.0, sample_query: nil } }

          sql_crumbs.each do |crumb|
            sql = crumb["m"].to_s
            next if sql.empty?

            fingerprint = normalize_sql(sql)
            group = groups[fingerprint]
            group[:count] += 1
            group[:total_duration_ms] += crumb["d"].to_f
            group[:sample_query] ||= sql
          end

          # Filter by threshold and sort by count desc
          groups
            .select { |_, v| v[:count] >= threshold }
            .map { |fingerprint, v| { fingerprint: fingerprint, count: v[:count], total_duration_ms: v[:total_duration_ms].round(2), sample_query: v[:sample_query] } }
            .sort_by { |p| -p[:count] }
        rescue => e
          []
        end

        # Normalize SQL for fingerprinting
        # Replaces literal values with ? placeholders while preserving structure
        # @param sql [String] Raw SQL query
        # @return [String] Normalized query
        def normalize_sql(sql)
          normalized = sql.to_s.dup

          # Replace single-quoted string literals with ?
          normalized.gsub!(/'[^']*'/, "?")

          # Replace IN (...) contents with single ?
          normalized.gsub!(/\bIN\s*\([^)]+\)/i, "IN (?)")

          # Replace standalone numeric literals with ?
          # Negative lookbehind for " to avoid replacing inside double-quoted identifiers
          normalized.gsub!(/(?<!")(?<!\w)\d+(?!\w)(?!")/, "?")

          normalized
        rescue => e
          sql.to_s
        end
      end
    end
  end
end
