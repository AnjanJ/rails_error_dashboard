# frozen_string_literal: true

module RailsErrorDashboard
  # Translation entry points for mailer templates.
  #
  # Mailers need two things the dashboard's I18nHelper does not provide.
  #
  # 1. AN UNESCAPED VARIANT, for the .text.erb parts.
  #
  #    red_t html-escapes, which is right for a web page and wrong for a plain
  #    text email: a French string would arrive in the recipient's mail client
  #    as "Impossible d&#39;accéder". The .html.erb parts still use red_t. The
  #    split mirrors I18nHelper vs. Translation elsewhere in the gem — the test
  #    is where the string lands, not what it looks like.
  #
  # 2. A DATE FORMATTER THAT DOES NOT DEPEND ON JAVASCRIPT.
  #
  #    ApplicationHelper#local_time renders a <span data-format> that the
  #    dashboard's JS re-renders in the reader's timezone and locale. Email has
  #    no JS, so a mailer must produce finished text server-side.
  #
  #    Ruby's strftime is not locale-aware: %B is "August" whatever RED's
  #    locale is. P3-T2 already put localized month, day and meridian names in
  #    red.js.* for the browser's formatDateTime(); red_mail_time substitutes
  #    the same vocabulary before handing the rest to strftime, so an email and
  #    the dashboard render a date identically.
  module MailerI18nHelper
    # red_locale and red_time_format live in I18nHelper. Include it explicitly
    # rather than relying on the mailer's view context happening to have both
    # mixed in: a helper that calls another helper without including it works
    # in a request and fails everywhere else, and the total rescues in this
    # path would swallow the NoMethodError into an empty string. That failure
    # mode already bit P2-T11 and P3-T3.
    include I18nHelper

    # Translate for a text/plain mailer part. Same lookup as red_t, no HTML
    # escaping. Use red_t in the .html.erb parts.
    #
    # @return [String] never nil, never raises
    def red_mail_t(key, **options)
      I18nStore.translate(key, locale: red_locale, **options)
    rescue StandardError
      ""
    end

    # Pluralized variant of red_mail_t.
    def red_mail_tp(key, count:, **options)
      red_mail_t(key, count: count, **options)
    end

    # A finished, localized timestamp for an email.
    #
    # @param time [Time, nil]
    # @param format [Symbol] a preset from red.time.formats
    # @return [String] "" for nil — a mailer must never render "undefined",
    #   and must never raise on the way to a notification
    def red_mail_time(time, format: :full)
      return "" if time.nil?

      utc = time.respond_to?(:utc) ? time.utc : time
      pattern = red_time_format(format)

      "#{Services::LocalizedTimeFormatter.call(utc, pattern: pattern, locale: red_locale)} UTC"
    rescue StandardError
      # A timestamp is worth losing; the notification is not.
      time.to_s
    end
  end
end
