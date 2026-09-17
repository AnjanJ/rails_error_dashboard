# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Find errors similar to a target error using fuzzy matching
    #
    # Uses SimilarityCalculator to compute similarity scores based on:
    # - Backtrace pattern similarity (70% weight)
    # - Message similarity (30% weight)
    #
    # Returns errors with similarity >= threshold, sorted by score descending
    class SimilarErrors
      # Find similar errors
      #
      # @param error_id [Integer] ID of target error
      # @param threshold [Float] Minimum similarity score (0.0-1.0), default 0.6
      # @param limit [Integer] Maximum number of results, default 10
      # @return [Array<Hash>] Array of {error: ErrorLog, similarity: Float}
      def self.call(error_id, threshold: 0.6, limit: 10)
        new(error_id, threshold: threshold, limit: limit).find_similar
      end

      def initialize(error_id, threshold: 0.6, limit: 10)
        @error_id = error_id
        @threshold = threshold.to_f
        @limit = limit.to_i
      end

      def find_similar
        target_error = ErrorLog.find_by(id: @error_id)
        return [] unless target_error

        # Find candidate errors to compare
        candidates = find_candidates(target_error)

        # Calculate similarity scores
        similar_errors = candidates.map do |candidate|
          score = Services::SimilarityCalculator.call(target_error, candidate)
          next if score < @threshold

          {
            error: candidate,
            similarity: score.round(3)
          }
        end.compact

        # Sort by similarity score (highest first) and limit results
        similar_errors.sort_by { |item| -item[:similarity] }.first(@limit)
      end

      private

      def find_candidates(target_error)
        # Build candidate query with multiple strategies for performance

        # Strategy 1: Same backtrace signature (fastest, most precise)
        candidates = []
        if target_error.backtrace_signature.present?
          candidates += ErrorLog
                          .where(backtrace_signature: target_error.backtrace_signature)
                          .where.not(id: target_error.id)
                          .limit(50)
        end

        # Strategy 2: Same error type (fast, good recall)
        if candidates.size < 20
          candidates += ErrorLog
                          .where(error_type: target_error.error_type)
                          .where.not(id: target_error.id)
                          .where.not(id: candidates.map(&:id))
                          .limit(30)
        end

        # Strategy 3: Same platform + same first word in error type
        # (catches similar errors like NoMethodError vs NameError)
        if candidates.size < 20 && target_error.platform.present?
          error_prefix = target_error.error_type&.split("::")&.last&.split(/(?=[A-Z])/, 2)&.first
          if error_prefix.present?
            candidates += ErrorLog
                            .where(platform: target_error.platform)
                            .where("error_type LIKE ? ESCAPE '!'", "%#{ActiveRecord::Base.sanitize_sql_like(error_prefix, "!")}%")
                            .where.not(id: target_error.id)
                            .where.not(id: candidates.map(&:id))
                            .limit(20)
          end
        end

        # Return unique candidates
        candidates.uniq
      end
    end
  end
end
