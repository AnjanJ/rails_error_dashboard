# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Infrastructure service: Clear analytics caches
    #
    # Clears dashboard_stats, analytics_stats, and platform_comparison
    # cache entries. Handles cache stores that don't support delete_matched
    # (e.g., SolidCache) gracefully.
    class AnalyticsCacheManager
      CACHE_PATTERNS = %w[
        dashboard_stats/*
        analytics_stats/*
        platform_comparison/*
      ].freeze

      # Clear all analytics caches
      def self.clear
        if Rails.cache.respond_to?(:delete_matched)
          CACHE_PATTERNS.each { |pattern| Rails.cache.delete_matched(pattern) }
        else
          Rails.logger.info("Cache store doesn't support delete_matched, skipping cache clear") if Rails.logger
        end
      rescue NotImplementedError => e
        Rails.logger.info("Cache store doesn't support delete_matched: #{e.message}") if Rails.logger
      rescue => e
        Rails.logger.error("Failed to clear analytics cache: #{e.message}") if Rails.logger
      end
    end
  end
end
