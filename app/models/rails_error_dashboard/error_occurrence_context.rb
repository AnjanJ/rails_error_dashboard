# frozen_string_literal: true

module RailsErrorDashboard
  # The moment-of-failure context of one occurrence: breadcrumbs, system
  # health, local and instance variables, the same JSON strings the error row
  # holds for its latest capture. Commands::RecordOccurrenceContext writes them
  # and keeps the newest config.occurrence_context_limit per error.
  class ErrorOccurrenceContext < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_error_occurrence_contexts"

    belongs_to :error_occurrence, class_name: "RailsErrorDashboard::ErrorOccurrence"
    belongs_to :error_log, class_name: "RailsErrorDashboard::ErrorLog"
  end
end
