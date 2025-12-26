# frozen_string_literal: true

module RailsErrorDashboard
  # Model: ErrorComment
  # Represents a comment/note on an error for team collaboration
  class ErrorComment < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_error_comments"

    belongs_to :error_log, class_name: "RailsErrorDashboard::ErrorLog"

    validates :author_name, presence: true, length: { maximum: 255 }
    validates :body, presence: true, length: { maximum: 10_000 }

    scope :recent_first, -> { order(created_at: :desc) }
    scope :oldest_first, -> { order(created_at: :asc) }

    # Get formatted timestamp for display
    def formatted_time
      created_at.strftime("%b %d, %Y at %I:%M %p")
    end

    # Check if comment was created recently (within last hour)
    def recent?
      created_at > 1.hour.ago
    end
  end
end
