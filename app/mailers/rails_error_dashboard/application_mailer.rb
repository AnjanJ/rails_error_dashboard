# frozen_string_literal: true

module RailsErrorDashboard
  class ApplicationMailer < ActionMailer::Base
    default from: -> { RailsErrorDashboard.configuration.notification_email_from }
    layout "mailer"
  end
end
