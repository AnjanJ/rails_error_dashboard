# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: Fetch critical/high priority unresolved errors from the last hour
    # Used on the overview dashboard to surface urgent issues
    class CriticalAlerts
      def self.call(application_id: nil, limit: 10)
        new(application_id: application_id, limit: limit).call
      end

      def initialize(application_id: nil, limit: 10)
        @application_id = application_id
        @limit = limit
      end

      def call
        scope = ErrorLog
          .where("occurred_at >= ?", 1.hour.ago)
          .where(resolved_at: nil)
          .where(priority_level: [ 3, 4 ])
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope.order(occurred_at: :desc).limit(@limit)
      end
    end
  end
end
