# frozen_string_literal: true

module RailsErrorDashboard
  class ErrorNotificationMailer < ApplicationMailer
    def error_alert(error_log, recipients)
      @error_log = error_log
      @dashboard_url = dashboard_url(error_log)

      mail(
        to: recipients,
        subject: "🚨 #{error_log.error_type}: #{truncate_subject(error_log.message)}"
      )
    end

    private

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
