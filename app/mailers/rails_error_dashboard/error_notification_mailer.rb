# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorNotificationMailer < ApplicationMailer
    # @param locale [String] resolved at enqueue time, never read from
    #   Current — a mailer renders outside the request that set it.
    def error_alert(error_log, recipients, locale: I18nStore::DEFAULT_LOCALE)
      @error_log = error_log
      @dashboard_url = dashboard_url(error_log)
      @red_locale = locale

      mail(
        to: recipients,
        subject: subject_for(error_log, locale)
      )
    end

    private

    # The subject is assembled from a key rather than interpolated inline, so a
    # locale can reorder or drop the emoji. error_type and message are verbatim
    # error content and are never translated.
    def subject_for(error_log, locale)
      I18nStore.translate(
        "red.mailers.error_alert.subject",
        locale: locale,
        application: error_log.application&.name ||
          I18nStore.translate("red.mailers.shared.unknown_application", locale: locale),
        error_type: error_log.error_type,
        message: truncate_subject(error_log.message)
      )
    end

    def dashboard_url(error_log)
      base_url = RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000"
      mount_path = RailsErrorDashboard.configuration.engine_mount_path
      "#{base_url}#{mount_path}/errors/#{error_log.id}"
    end

    def truncate_subject(message)
      return "" unless message
      message.length > 50 ? "#{message[0...50]}..." : message
    end
  end
end
