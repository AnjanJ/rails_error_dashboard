# frozen_string_literal: true

module RailsErrorDashboard
  class DigestMailer < ApplicationMailer
    def digest_summary(digest, recipients)
      @digest = digest
      @dashboard_url = dashboard_base_url

      mail(
        to: recipients,
        subject: "RED Digest — #{digest[:stats][:new_errors]} new errors (#{digest[:period_label]})"
      )
    end

    private

    def dashboard_base_url
      RailsErrorDashboard.configuration.dashboard_base_url || "http://localhost:3000"
    end
  end
end
