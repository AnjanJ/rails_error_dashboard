# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Storm protection episode history + active-storm lookup.
    #
    # Read-only. Powers the /errors/storms page and the layout banner.
    class StormHistory
      RECENT_BANNER_WINDOW = 24.hours

      def self.call(limit: 50)
        return { active: nil, recent: nil, events: [] } unless StormEvent.table_exists?

        {
          active: StormEvent.active.recent_first.first,
          recent: StormEvent.ended_within(RECENT_BANNER_WINDOW).recent_first.first,
          events: StormEvent.recent_first.limit(limit).to_a
        }
      rescue => e
        RailsErrorDashboard::Logger.error(
          "[RailsErrorDashboard] StormHistory query failed: #{e.message}"
        )
        { active: nil, recent: nil, events: [] }
      end

      # Cheap banner lookup for the layout — one indexed query on the happy
      # path (no active storm), two when a banner is showing.
      def self.banner_event
        return nil unless RailsErrorDashboard.configuration.enable_storm_protection
        return nil unless StormEvent.table_exists?

        StormEvent.active.recent_first.first ||
          StormEvent.ended_within(RECENT_BANNER_WINDOW).recent_first.first
      rescue
        nil
      end
    end
  end
end
