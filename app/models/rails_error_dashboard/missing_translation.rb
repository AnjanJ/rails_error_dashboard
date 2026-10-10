# frozen_string_literal: true

module RailsErrorDashboard
  # A translation key the host app looked up and did not have, counted per
  # (locale, key, application).
  #
  # Rows are written by Commands::FlushMissingTranslations from the tracker's
  # in-memory buffer, never one per lookup. Inherits ErrorLogsRecord so
  # separate-database routing applies.
  class MissingTranslation < ErrorLogsRecord
    self.table_name = "rails_error_dashboard_missing_translations"

    # Not a translation key: a synthetic row holding the misses the tracker
    # dropped because its per-thread buffer was full, kept so the totals the
    # dashboard shows are never silently understated. Stored under a locale
    # no real lookup uses.
    OVERFLOW_KEY = "__overflow__"
    OVERFLOW_LOCALE = "*"

    belongs_to :application, optional: true

    validates :locale, presence: true
    validates :translation_key, presence: true
    validates :miss_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :for_application, ->(app_id) { where(application_id: app_id) }
    scope :seen_since, ->(time) { where("last_seen_at >= ?", time) }
    scope :overflow, -> { where(translation_key: OVERFLOW_KEY) }
    scope :real, -> { where.not(translation_key: OVERFLOW_KEY) }

    # The table may not be migrated yet on a host that upgraded the gem before
    # running the migration. Everything that touches this model on a request
    # path checks first and must never raise.
    def self.table_exists?
      connection.table_exists?(table_name)
    rescue *Commands::LogError::RETRYABLE_STORE_ERRORS
      raise
    rescue StandardError
      false
    end
  end
end
