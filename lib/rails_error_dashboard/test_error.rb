# frozen_string_literal: true

module RailsErrorDashboard
  # Custom exception class for test errors triggered from the dashboard.
  # Clearly identifiable in error lists so users know it's not a real issue.
  class TestError < StandardError; end
end
