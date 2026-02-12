# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Pure algorithm: Calculate priority score (0-100) for an error log
    #
    # Weighted average of 4 factors:
    # - Severity (40%): Based on error type classification
    # - Frequency (25%): Logarithmic scale of occurrence count
    # - Recency (20%): How recently the error occurred
    # - User Impact (15%): How many unique users are affected
    class PriorityScoreCalculator
      SEVERITY_WEIGHT = 0.4
      FREQUENCY_WEIGHT = 0.25
      RECENCY_WEIGHT = 0.2
      USER_IMPACT_WEIGHT = 0.15

      # Compute priority score for an error log
      # @param error_log [ErrorLog] The error log record
      # @return [Integer] Score 0-100
      def self.compute(error_log)
        severity_score = severity_to_score(error_log.severity)
        frequency_score = frequency_to_score(error_log.occurrence_count)
        recency_score = recency_to_score(error_log.occurred_at)
        impact_score = user_impact_to_score(error_log)

        (severity_score * SEVERITY_WEIGHT +
         frequency_score * FREQUENCY_WEIGHT +
         recency_score * RECENCY_WEIGHT +
         impact_score * USER_IMPACT_WEIGHT).round
      end

      # @param severity [Symbol] :critical, :high, :medium, :low
      # @return [Integer] Score 0-100
      def self.severity_to_score(severity)
        case severity
        when :critical then 100
        when :high then 75
        when :medium then 50
        when :low then 25
        else 10
        end
      end

      # Logarithmic scale: 1 occurrence = 10, 10 = 50, 100 = 90, 1000+ = 100
      # @param count [Integer] Occurrence count
      # @return [Integer] Score 0-100
      def self.frequency_to_score(count)
        count = count.to_i
        return 10 if count <= 1
        return 100 if count >= 1000

        (10 + (Math.log10(count) * 30)).clamp(10, 100).round
      end

      # Score based on how recently the error occurred
      # @param time [Time] When the error occurred
      # @return [Integer] Score 0-100
      def self.recency_to_score(time)
        return 10 if time.nil?

        hours_ago = ((Time.current - time) / 1.hour).to_i
        return 100 if hours_ago < 1      # Last hour
        return 80 if hours_ago < 24      # Last 24h
        return 50 if hours_ago < 168     # Last week
        return 20 if hours_ago < 720     # Last month

        10
      end

      # Score based on unique users affected
      # @param error_log [ErrorLog] The error log record
      # @return [Integer] Score 0-100
      def self.user_impact_to_score(error_log)
        return 0 unless error_log.user_id.present?

        total_users = unique_users_affected(error_log.error_type)
        return 0 if total_users.zero?

        (10 + (Math.log10(total_users + 1) * 30)).clamp(0, 100).round
      end

      # Count unique users affected by this error type
      # @param error_type [String] The error type
      # @return [Integer] Count of unique users
      def self.unique_users_affected(error_type)
        ErrorLog.where(error_type: error_type, resolved: false)
                .where.not(user_id: nil)
                .distinct
                .count(:user_id)
      end
    end
  end
end
