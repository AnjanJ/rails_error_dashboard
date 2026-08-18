# frozen_string_literal: true

module RailsErrorDashboard
  class ApplicationMailer < ActionMailer::Base
    default from: -> { RailsErrorDashboard.configuration.notification_email_from }
    layout false

    # Mailers do not pick up engine helpers the way controllers do, so these
    # are included explicitly.
    #
    # I18nHelper gives the .html.erb parts red_t; MailerI18nHelper adds
    # red_mail_t (unescaped, for the .text.erb parts) and red_mail_time (a
    # localized timestamp that needs no JavaScript).
    #
    # The locale arrives as an explicit argument and is assigned to
    # @red_locale, which I18nHelper#red_locale prefers over Current — a mailer
    # renders outside the request that set Current, and on a reused thread
    # Current holds an unrelated request's value (P4-T1).
    helper RailsErrorDashboard::I18nHelper
    helper RailsErrorDashboard::MailerI18nHelper
  end
end
