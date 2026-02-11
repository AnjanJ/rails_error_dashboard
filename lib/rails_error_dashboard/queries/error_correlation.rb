# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query object for error correlation analysis
    #
    # Provides analytics for correlating errors with:
    # - Releases (app_version, git_sha)
    # - Users (affected users, multi-error users)
    # - Time patterns (hour-of-day correlation)
    #
    # @example
    #   correlation = ErrorCorrelation.new(days: 30)
    #   correlation.errors_by_version
    #   # => { "1.0.0" => { count: 100, error_types: 15, critical_count: 5 } }
    class ErrorCorrelation
      attr_reader :days, :application_id

      # @param days [Integer] Number of days to analyze (default: 30)
      # @param application_id [Integer, nil] Optional application ID to filter by
      def initialize(days: 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      # Get error statistics grouped by app version
      # @return [Hash] Version => { count, error_types, critical_count, platforms }
      def errors_by_version
        return {} unless has_version_column?

        versions = base_query
          .where.not(app_version: nil)
          .group(:app_version)
          .count

        versions.each_with_object({}) do |(version, count), result|
          errors = base_query.where(app_version: version)

          # Count unique error types
          error_types = errors.distinct.pluck(:error_type).count

          # Count critical errors
          critical_count = errors.select { |error| error.severity == :critical }.count

          # Get platforms for this version
          platforms = errors.distinct.pluck(:platform).compact

          result[version] = {
            count: count,
            error_types: error_types,
            critical_count: critical_count,
            platforms: platforms,
            first_seen: errors.minimum(:occurred_at),
            last_seen: errors.maximum(:occurred_at)
          }
        end
      end

      # Get error statistics grouped by git SHA
      # @return [Hash] SHA => { count, error_types, app_version }
      def errors_by_git_sha
        return {} unless has_git_sha_column?

        shas = base_query
          .where.not(git_sha: nil)
          .group(:git_sha)
          .count

        shas.each_with_object({}) do |(sha, count), result|
          errors = base_query.where(git_sha: sha)

          # Get associated version (may be multiple)
          versions = errors.distinct.pluck(:app_version).compact

          result[sha] = {
            count: count,
            error_types: errors.distinct.pluck(:error_type).count,
            app_versions: versions,
            first_seen: errors.minimum(:occurred_at),
            last_seen: errors.maximum(:occurred_at)
          }
        end
      end

      # Find problematic releases (versions with >2x average error rate)
      # @return [Array<Hash>] Array of problematic version data
      def problematic_releases
        return [] unless has_version_column?

        versions_data = errors_by_version
        return [] if versions_data.empty?

        total_errors = versions_data.values.map { |v| v[:count] }.sum
        avg_errors = total_errors.to_f / versions_data.count
        threshold = avg_errors * 2

        versions_data
          .select { |_, data| data[:count] > threshold }
          .map do |version, data|
            deviation = avg_errors > 0 ? ((data[:count] - avg_errors) / avg_errors * 100).round(1) : 0.0

            {
              version: version,
              error_count: data[:count],
              deviation_from_avg: deviation,
              critical_count: data[:critical_count],
              error_types: data[:error_types],
              platforms: data[:platforms]
            }
          end
          .sort_by { |v| -v[:error_count] }
      end

      # Find users affected by multiple different error types
      # @param min_error_types [Integer] Minimum number of different error types (default: 2)
      # @return [Array<Hash>] Users with multiple error type exposure
      def multi_error_users(min_error_types: 2)
        users_with_errors = base_query
          .where.not(user_id: nil)
          .group(:user_id, :error_type)
          .count

        # Group by user_id
        users_by_id = users_with_errors.group_by { |(user_id, _), _| user_id }

        users_by_id
          .select { |_, error_data| error_data.count >= min_error_types }
          .map do |user_id, error_data|
            error_type_names = error_data.map { |(_, type), _| type }
            total_errors = error_data.map { |_, count| count }.sum

            {
              user_id: user_id,
              user_email: find_user_email(user_id),
              error_types: error_type_names,
              error_type_count: error_type_names.count,
              total_errors: total_errors
            }
          end
          .sort_by { |u| -u[:error_type_count] }
      end

      # Calculate user overlap between two error types
      # Returns percentage of users affected by both errors
      # @param error_type_a [String] First error type
      # @param error_type_b [String] Second error type
      # @return [Hash] Overlap statistics
      def error_type_user_overlap(error_type_a, error_type_b)
        users_a = base_query
          .where(error_type: error_type_a)
          .where.not(user_id: nil)
          .distinct
          .pluck(:user_id)

        users_b = base_query
          .where(error_type: error_type_b)
          .where.not(user_id: nil)
          .distinct
          .pluck(:user_id)

        overlap = users_a & users_b

        {
          error_type_a: error_type_a,
          error_type_b: error_type_b,
          users_a_count: users_a.count,
          users_b_count: users_b.count,
          overlap_count: overlap.count,
          overlap_percentage: calculate_percentage(overlap.count, [ users_a.count, users_b.count ].min),
          overlapping_user_ids: overlap.first(10) # Sample of overlapping users
        }
      end

      # Analyze time-based correlation between error types
      # Finds error types that tend to occur at similar hours of day
      # @return [Hash] Error type pairs with correlation scores
      def time_correlated_errors
        # Get hourly distribution for each error type
        error_types = base_query.distinct.pluck(:error_type)
        return {} if error_types.count < 2

        hourly_distributions = {}
        error_types.each do |error_type|
          distribution = base_query
            .where(error_type: error_type)
            .group_by { |error| error.occurred_at.hour }
            .transform_values(&:count)

          # Normalize to 0-23 hours
          hourly_distributions[error_type] = (0..23).map { |h| distribution[h] || 0 }
        end

        # Calculate correlation between error type pairs
        correlations = {}
        error_types.combination(2).each do |type_a, type_b|
          correlation = Services::PearsonCorrelation.call(
            hourly_distributions[type_a],
            hourly_distributions[type_b]
          )

          # Only include significant correlations (>0.5)
          if correlation > 0.5
            correlations["#{type_a} <-> #{type_b}"] = {
              error_type_a: type_a,
              error_type_b: type_b,
              correlation: correlation,
              strength: Services::StatisticalClassifier.correlation_strength(correlation)
            }
          end
        end

        correlations.sort_by { |_, v| -v[:correlation] }.to_h
      end

      # Compare error rates across different time periods
      # @return [Hash] Comparison of current vs previous period
      def period_comparison
        current_start = (@days / 2).days.ago
        previous_start = @start_date
        previous_end = current_start

        current_errors = ErrorLog
          .where("occurred_at >= ?", current_start)
          .count

        previous_errors = ErrorLog
          .where("occurred_at >= ? AND occurred_at < ?", previous_start, previous_end)
          .count

        change_percentage = if previous_errors > 0
          ((current_errors - previous_errors).to_f / previous_errors * 100).round(1)
        else
          current_errors > 0 ? 100.0 : 0.0
        end

        {
          current_period: {
            start: current_start,
            end: Time.current,
            count: current_errors
          },
          previous_period: {
            start: previous_start,
            end: previous_end,
            count: previous_errors
          },
          change: current_errors - previous_errors,
          change_percentage: change_percentage,
          trend: Services::StatisticalClassifier.trend_direction(change_percentage)
        }
      end

      # Get top error types by platform
      # Shows which errors are platform-specific vs cross-platform
      # @return [Hash] Platform => top error types
      def platform_specific_errors
        platforms = base_query.distinct.pluck(:platform).compact

        platforms.each_with_object({}) do |platform, result|
          platform_errors = base_query.where(platform: platform)
          top_errors = platform_errors
            .group(:error_type)
            .count
            .sort_by { |_, count| -count }
            .first(5)

          result[platform] = top_errors.map do |error_type, count|
            # Check if this error occurs on other platforms
            other_platforms = base_query
              .where(error_type: error_type)
              .where.not(platform: platform)
              .distinct
              .pluck(:platform)
              .compact

            {
              error_type: error_type,
              count: count,
              platform_specific: other_platforms.empty?,
              also_on: other_platforms
            }
          end
        end
      end

      private

      def base_query
        scope = ErrorLog.where("occurred_at >= ?", @start_date)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      # Check if app_version column exists
      def has_version_column?
        ErrorLog.column_names.include?("app_version")
      end

      # Check if git_sha column exists
      def has_git_sha_column?
        ErrorLog.column_names.include?("git_sha")
      end

      # Find user email
      def find_user_email(user_id)
        user_model = RailsErrorDashboard.configuration.user_model
        user = user_model.constantize.find_by(id: user_id)
        user&.email || "User ##{user_id}"
      rescue StandardError
        "User ##{user_id}"
      end

      # Calculate percentage
      def calculate_percentage(part, whole)
        return 0.0 if whole.zero?
        (part.to_f / whole * 100).round(1)
      end
    end
  end
end
