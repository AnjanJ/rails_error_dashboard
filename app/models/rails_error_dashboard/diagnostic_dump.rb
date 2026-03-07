# frozen_string_literal: true

module RailsErrorDashboard
  class DiagnosticDump < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_diagnostic_dumps"

    belongs_to :application

    validates :captured_at, presence: true
    validates :dump_data, presence: true

    scope :recent, -> { order(captured_at: :desc) }
  end
end
