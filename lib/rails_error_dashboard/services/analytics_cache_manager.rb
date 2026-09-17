# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Infrastructure service: invalidate the dashboard's cached statistics
    #
    # Every cached stats key (DashboardStats, AnalyticsStats) embeds a
    # GENERATION number read from Rails.cache. Invalidation is one increment of
    # that number: entries written under the old generation are simply never
    # read again and age out by their own TTL.
    #
    # This replaced delete_matched("dashboard_stats/*") and friends, which is a
    # SCAN of the HOST app's whole Redis keyspace, NotImplementedError on
    # memcached, and used to run from ErrorLog's after_save -- i.e. inside the
    # host's request thread on every captured error.
    #
    # Who calls .clear: user actions and maintenance that change what the cards
    # show (resolve, status change, batch actions, mute, retention). Captures
    # deliberately do NOT: they rely on the TTL (1 minute for the stat cards,
    # 5 for analytics), which decouples capture cost from dashboard freshness.
    #
    # With :memory_store the generation is per process, so an action handled by
    # one worker reaches the others when their entries expire. With :null_store
    # nothing is cached and there is nothing to invalidate.
    class AnalyticsCacheManager
      GENERATION_KEY = "red/cache_gen"

      # @return [Integer] the current cache generation; 0 when unset or unreadable
      def self.generation
        Rails.cache.read(GENERATION_KEY).to_i
      rescue => e
        RailsErrorDashboard::Logger.debug("[RailsErrorDashboard] cache generation unreadable: #{e.class}: #{e.message}")
        0
      end

      # Invalidate every cached dashboard statistic. Never raises.
      #
      # A plain read + write, deliberately not Rails.cache.increment: increment
      # is unimplemented on some stores, returns nil for a missing key on
      # others, and on Redis is an INCRBY that fails against an entry written
      # by #write. It does not need to be atomic either -- racing clears only
      # need the number to differ from the one stale entries were written under.
      #
      # Never lower than the clock in milliseconds, so that a store which evicts
      # the generation key cannot restart at a number that entries still inside
      # their TTL were written under a few minutes earlier.
      def self.clear
        Rails.cache.write(GENERATION_KEY, [ generation + 1, (Time.now.to_f * 1000).to_i ].max)
        nil
      rescue => e
        RailsErrorDashboard::Logger.error("[RailsErrorDashboard] Failed to clear analytics cache: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
