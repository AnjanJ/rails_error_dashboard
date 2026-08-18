# frozen_string_literal: true

module RailsErrorDashboard
  class DigestMailer < ApplicationMailer
    # @param locale [String] resolved at enqueue time, never read from
    #   Current — a mailer renders outside the request that set it.
    def digest_summary(digest, recipients, locale: I18nStore::DEFAULT_LOCALE)
      @digest = digest
      @dashboard_url = dashboard_base_url
      @red_locale = locale

      mail(
        to: recipients,
        subject: "RED Digest — #{digest[:stats][:new_errors]} new errors (#{digest[:period_label]})"
      )
    end

    private

    def dashboard_base_url
      base = RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000"
      mount_path = RailsErrorDashboard.configuration.engine_mount_path
      "#{base}#{mount_path}"
    end
  end
end
