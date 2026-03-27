# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Build a release timeline from error data, showing per-version health stats,
    # "new in this release" error detection, stability indicators, and release-over-release deltas.
    # Uses existing app_version and git_sha columns on error_logs — no new migration needed.
    class ReleaseTimeline
      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      def call
        return empty_result unless has_version_column?

        releases = build_releases
        {
          releases: releases,
          summary: build_summary(releases)
        }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] ReleaseTimeline failed: #{e.class}: #{e.message}")
        empty_result
      end

      private

      def base_scope
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
                        .where.not(app_version: [ nil, "" ])
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def build_releases
        version_stats = aggregate_version_stats
        return [] if version_stats.empty?

        new_errors = new_errors_per_version
        avg_errors = version_stats.sum { |_v, s| s[:total_errors] }.to_f / version_stats.size

        # Sort chronologically by first_seen (oldest first) for delta calculation
        sorted_chrono = version_stats.sort_by { |_v, s| s[:first_seen] }

        releases = []
        sorted_chrono.each_with_index do |(version, stats), idx|
          previous_count = idx > 0 ? sorted_chrono[idx - 1][1][:total_errors] : nil

          releases << {
            version: version,
            git_shas: stats[:git_shas],
            first_seen: stats[:first_seen],
            last_seen: stats[:last_seen],
            current: false, # set below
            total_errors: stats[:total_errors],
            unique_error_types: stats[:unique_error_types],
            new_error_count: new_errors[version] || 0,
            stability: stability_indicator(stats[:total_errors], avg_errors),
            problematic: stats[:total_errors] > (avg_errors * 2),
            delta_from_previous: previous_count ? (stats[:total_errors] - previous_count) : nil,
            delta_percentage: previous_count && previous_count > 0 ? ((stats[:total_errors] - previous_count).to_f / previous_count * 100).round(1) : nil
          }
        end

        # Mark the most recent release as current
        releases.last[:current] = true if releases.any?

        # Return in reverse chronological order (newest first)
        releases.reverse
      end

      # Single GROUP BY query for per-version aggregates
      def aggregate_version_stats
        rows = base_scope
          .group(:app_version)
          .select(
            :app_version,
            "COUNT(*) AS total_count",
            "COUNT(DISTINCT error_type) AS unique_types",
            "MIN(occurred_at) AS first_seen_at",
            "MAX(occurred_at) AS last_seen_at"
          )

        # Collect git_shas per version in a second lightweight query
        sha_map = {}
        if has_git_sha_column?
          base_scope.where.not(git_sha: [ nil, "" ])
                    .group(:app_version, :git_sha)
                    .pluck(:app_version, :git_sha)
                    .each do |version, sha|
                      (sha_map[version] ||= []) << sha
                    end
          sha_map.each_value(&:uniq!)
        end

        rows.each_with_object({}) do |row, result|
          version = row.app_version
          first_seen = row.first_seen_at
          last_seen = row.last_seen_at
          first_seen = Time.zone.parse(first_seen) if first_seen.is_a?(String)
          last_seen = Time.zone.parse(last_seen) if last_seen.is_a?(String)

          result[version] = {
            total_errors: row.total_count.to_i,
            unique_error_types: row.unique_types.to_i,
            first_seen: first_seen,
            last_seen: last_seen,
            git_shas: sha_map[version] || []
          }
        end
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] ReleaseTimeline aggregate failed: #{e.class}: #{e.message}")
        {}
      end

      # For each error_hash in the window, find which app_version it first appeared in.
      # Count per version to get "new errors introduced in this release".
      def new_errors_per_version
        return {} unless has_error_hash_column?

        # Get the earliest occurrence per error_hash, with its app_version
        # We need (error_hash, app_version) at MIN(occurred_at)
        earliest = {}
        base_scope.select(:error_hash, :app_version, :occurred_at)
                  .where.not(error_hash: [ nil, "" ])
                  .order(:occurred_at)
                  .each do |row|
                    earliest[row.error_hash] ||= row.app_version
                  end

        # Count how many error_hashes have each version as their earliest
        earliest.values.tally
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] ReleaseTimeline new_errors failed: #{e.class}: #{e.message}")
        {}
      end

      def stability_indicator(count, avg)
        return :green if avg <= 0
        ratio = count.to_f / avg
        if ratio <= 1.0
          :green
        elsif ratio <= 2.0
          :yellow
        else
          :red
        end
      end

      def build_summary(releases)
        {
          total_releases: releases.size,
          current_version: releases.first&.dig(:version),
          avg_errors_per_release: releases.any? ? (releases.sum { |r| r[:total_errors] }.to_f / releases.size).round(1) : 0
        }
      end

      def empty_result
        { releases: [], summary: { total_releases: 0, current_version: nil, avg_errors_per_release: 0 } }
      end

      def has_version_column?
        ErrorLog.column_names.include?("app_version")
      end

      def has_git_sha_column?
        ErrorLog.column_names.include?("git_sha")
      end

      def has_error_hash_column?
        ErrorLog.column_names.include?("error_hash")
      end
    end
  end
end
