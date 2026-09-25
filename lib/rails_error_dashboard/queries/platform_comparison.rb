# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query object for comparing error metrics across platforms
    #
    # Provides analytics comparing iOS vs Android vs API vs Web platforms:
    # - Error rates and trends
    # - Severity distribution
    # - Resolution times
    # - Top errors per platform
    # - Platform stability scores
    # - Cross-platform errors
    #
    # Two counting units, kept distinct on purpose -- the same split as
    # AnalyticsStats, for the same reason.
    #
    #   EVENT figures  -> Queries::EventVolume: how much erroring happened in
    #                     the window. Error rate, daily trend, severity
    #                     distribution, cross-platform totals, the top-errors
    #                     ranking, and the health card's total, critical count
    #                     and velocity.
    #   GROUP figures  -> groups FIRST SEEN in the window: the state of
    #                     distinct errors. Unresolved count, resolution rate and
    #                     resolution time. A group is what gets resolved; an
    #                     event cannot be.
    #
    # An ErrorLog row is a GROUP and its occurred_at is FIRST-SEEN. Selecting
    # groups by it and counting them made a group born last month that recurs
    # today invisible here -- zero errors on this page (and on the Overview's
    # platform health card) while the Overview's own total counted the event.
    #
    # @example
    #   comparison = PlatformComparison.new(days: 7)
    #   comparison.error_rate_by_platform
    #   # => { "ios" => 150, "android" => 200, "api" => 50, "web" => 100 }
    class PlatformComparison
      attr_reader :days, :application_id

      # @param days [Integer] Number of days to analyze (default: 7)
      # @param application_id [Integer, nil] Optional application ID to filter by
      def initialize(days: 7, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      private

      # Every group of the selected application, NOT cut by date. EventVolume
      # must be handed this: a scope already filtered by first-seen drops the
      # events of every older group that recurred inside the window.
      # @return [ActiveRecord::Relation]
      def base_scope
        scope = ErrorLog.all
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      def platforms
        @platforms ||= base_scope.distinct.pluck(:platform).compact
      end

      def volume
        @volume ||= Queries::EventVolume.new(base_scope, @start_date)
      end

      # platform => { error_type => events in the window }.
      #
      # Severity, critical counts and cross-platform totals all fold from this
      # one breakdown, so they cannot drift from each other, and each platform's
      # parts sum to its error rate (the same primitive, exhaustively grouped).
      def type_volume_by_platform
        @type_volume_by_platform ||= platforms.index_with do |platform|
          Queries::EventVolume.by_group_attribute(base_scope.where(platform: platform), :error_type, @start_date)
        end
      end

      public

      # Events per platform in the window.
      # @return [Hash] Platform name => event count
      def error_rate_by_platform
        # select, not the raw breakdown: that is a Hash.new(0), and a platform
        # with no events must read as absent (nil), not as a silent zero.
        @error_rate_by_platform ||= volume.by_group_attribute(:platform).select { |_, count| count.positive? }
      end

      # Events per platform, by severity of their error type.
      # @return [Hash] Platform => { severity => count }
      def severity_distribution_by_platform
        type_volume_by_platform.transform_values do |counts_by_type|
          counts_by_type.each_with_object(Hash.new(0)) do |(error_type, count), severities|
            severities[Services::SeverityClassifier.classify(error_type)] += count
          end
        end
      end

      # Get average resolution time by platform
      # GROUP figure: a resolution belongs to a group, selected by first-seen.
      # @return [Hash] Platform => average hours to resolve
      def resolution_time_by_platform
        platforms = base_scope.distinct.pluck(:platform).compact

        platforms.each_with_object({}) do |platform, result|
          resolved_errors = base_scope
            .where(platform: platform)
            .where.not(resolved_at: nil)
            .where("occurred_at >= ?", @start_date)

          if resolved_errors.any?
            total_hours = resolved_errors.sum do |error|
              ((error.resolved_at - error.occurred_at) / 3600.0).round(2)
            end
            result[platform] = (total_hours / resolved_errors.count).round(2)
          else
            result[platform] = nil
          end
        end
      end

      # Top 10 groups per platform, ranked by their events in the window.
      #
      # :occurrence_count is the group's count WITHIN the window, not its
      # lifetime total -- the key is kept so the view and callers are
      # unchanged. The per-group breakdown holds one integer pair per group
      # with events in the window; only the top ten rows are loaded.
      # @return [Hash] Platform => Array of error hashes
      def top_errors_by_platform
        platforms.each_with_object({}) do |platform, result|
          events_by_group = Queries::EventVolume.by_group_attribute(
            base_scope.where(platform: platform), :id, @start_date
          )
          top = events_by_group.select { |_, count| count.positive? }
                               .sort_by { |id, count| [ -count, id ] }
                               .first(10)
          groups = ErrorLog.where(id: top.map(&:first))
                           .select(:id, :error_type, :message, :occurred_at)
                           .index_by(&:id)

          result[platform] = top.filter_map do |id, count|
            error = groups[id]
            next unless error

            {
              id: error.id,
              error_type: error.error_type,
              message: error.message&.truncate(100),
              severity: error.severity, # Calls the method
              occurrence_count: count,
              occurred_at: error.occurred_at
            }
          end
        end
      end

      # Calculate platform stability score (0-100)
      # Higher score = more stable (fewer errors, faster resolution)
      # @return [Hash] Platform => stability score
      def platform_stability_scores
        platforms = base_scope.distinct.pluck(:platform).compact
        error_rates = error_rate_by_platform
        resolution_times = resolution_time_by_platform

        # Find max values for normalization
        max_errors = error_rates.values.max || 1
        max_resolution_time = resolution_times.values.compact.max || 1

        platforms.each_with_object({}) do |platform, result|
          error_count = error_rates[platform] || 0
          avg_resolution = resolution_times[platform] || 0

          # Normalize to 0-1 scale (inverted - lower is better)
          error_score = 1.0 - (error_count.to_f / max_errors)
          resolution_score = avg_resolution.positive? ? 1.0 - (avg_resolution / max_resolution_time) : 1.0

          # Weight: 70% error count, 30% resolution time
          # Convert to 0-100 scale
          result[platform] = ((error_score * 0.7 + resolution_score * 0.3) * 100).round(1)
        end
      end

      # Error types with events on more than one platform in the window.
      # @return [Array<Hash>] Errors with their platforms
      def cross_platform_errors
        by_type = Hash.new { |hash, error_type| hash[error_type] = {} }
        type_volume_by_platform.each do |platform, counts_by_type|
          counts_by_type.each do |error_type, count|
            by_type[error_type][platform] = count if count.positive?
          end
        end

        by_type
          .select { |_, breakdown| breakdown.size > 1 }
          .map do |error_type, breakdown|
            {
              error_type: error_type,
              platforms: breakdown.keys.sort,
              total_occurrences: breakdown.values.sum,
              platform_breakdown: breakdown
            }
          end
          .sort_by { |error| -error[:total_occurrences] }
      end

      # Events per day per platform, on the day each event HAPPENED.
      #
      # The zero-filled date range is preserved: the chart needs a point for
      # every day in the window, not only the days that had errors.
      # @return [Hash] Platform => { date => count }
      def daily_trend_by_platform
        days = (@start_date.to_date..Date.current)

        platforms.index_with do |platform|
          counts = Queries::EventVolume.by_day(base_scope.where(platform: platform), @start_date)
          days.to_h { |day| [ day, counts[day] || 0 ] }
        end
      end

      # Get platform health summary
      # @return [Hash] Platform => health metrics
      def platform_health_summary
        error_rates = error_rate_by_platform
        stability_scores = platform_stability_scores
        severities = severity_distribution_by_platform
        midpoint = @start_date + (@days / 2.0).days

        platforms.each_with_object({}) do |platform, result|
          platform_scope = base_scope.where(platform: platform)
          groups_in_window = platform_scope.where("occurred_at >= ?", @start_date)

          # EVENT figures: part of the same volume as the error rate.
          total_errors = error_rates[platform] || 0
          critical_errors = severities.fetch(platform, {})[:critical] || 0

          # GROUP figures. The resolution rate divides groups by groups; divided
          # by the event total it would mix units and stop meaning anything.
          unresolved_errors = groups_in_window.where(resolved_at: nil).count
          resolved_errors = groups_in_window.where.not(resolved_at: nil).count
          total_groups = unresolved_errors + resolved_errors
          resolution_rate = total_groups.positive? ? ((resolved_errors.to_f / total_groups) * 100).round(1) : 0.0

          # Error velocity: events in the second half of the window against the
          # first, each counted where it happened.
          first_half = Queries::EventVolume.in_window(platform_scope, @start_date, midpoint)
          second_half = Queries::EventVolume.in_window(platform_scope, midpoint)

          velocity = first_half.positive? ? (((second_half - first_half).to_f / first_half) * 100).round(1) : 0.0

          result[platform] = {
            total_errors: total_errors,
            critical_errors: critical_errors,
            unresolved_errors: unresolved_errors,
            resolution_rate: resolution_rate,
            stability_score: stability_scores[platform] || 0,
            error_velocity: velocity, # Positive = increasing, negative = decreasing
            health_status: determine_health_status(stability_scores[platform] || 0, velocity)
          }
        end
      end

      private

      # Determine health status based on stability score and velocity
      # @param stability_score [Float] 0-100 stability score
      # @param velocity [Float] Error velocity percentage
      # @return [Symbol] :healthy, :warning, or :critical
      def determine_health_status(stability_score, velocity)
        if stability_score >= 80 && velocity <= 10
          :healthy
        elsif stability_score >= 60 && velocity <= 50
          :warning
        else
          :critical
        end
      end
    end
  end
end
