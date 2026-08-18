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

    # The directives whose output is a *word*, and therefore locale-dependent:
    # %B %b (month), %A %a (weekday), %p %P (meridian). Everything else
    # (%Y, %m, %d, %H, %M, %S, %Z …) is digits or a timezone abbreviation and
    # is left to strftime.
    LOCALIZED_DIRECTIVES = /%[BbAaPp]/

    # Stand-in for a localized word while strftime runs. Contains no percent,
    # so strftime cannot read it as a directive, and no space, so it cannot
    # alter the spacing the pattern asked for. The index keeps two occurrences
    # of the same directive independent.
    PLACEHOLDER = "\u0000RED%<index>d\u0000"

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

      "#{localized_strftime(utc, pattern)} UTC"
    rescue StandardError
      # A timestamp is worth losing; the notification is not.
      time.to_s
    end

    private

    # strftime with the word-producing directives replaced from RED's
    # dictionary first.
    #
    # Two-pass, via placeholders: substituting a translated month name
    # directly would put arbitrary text into the pattern, and a French
    # "%A" -> "mardi" is harmless but a translation containing a literal
    # percent sign would corrupt every directive after it. The placeholder
    # carries no percent, so strftime cannot misread it.
    def localized_strftime(time, pattern)
      replacements = []

      staged = pattern.gsub(LOCALIZED_DIRECTIVES) do |directive|
        word = localized_word(directive, time)
        next directive if word.nil?

        replacements << word
        format(PLACEHOLDER, index: replacements.length - 1)
      end

      rendered = time.strftime(staged)

      replacements.each_with_index do |word, index|
        rendered = rendered.sub(format(PLACEHOLDER, index: index), word)
      end

      rendered
    end

    # @return [String, nil] nil means "leave it to strftime"
    def localized_word(directive, time)
      case directive
      when "%B" then name_array(:months, 12)[time.month - 1]
      when "%b" then name_array(:months_short, 12)[time.month - 1]
      when "%A" then name_array(:days, 7)[time.wday]
      when "%a" then name_array(:days_short, 7)[time.wday]
      when "%p" then meridian_for(time)
      when "%P" then meridian_for(time)&.downcase
      end
    end

    # I18nStore.subtree returns SYMBOL keys — the backend loads the YAML
    # symbolized. Indexing with a String silently yields nil here, and because
    # a nil array falls back to English the bug looks exactly like "this locale
    # has no translation" rather than like a defect. Caught in P4-T2 by a spec
    # that asserted a translated month name and got the English one.
    #
    # A locale that translates only some of these must not produce a mix of
    # translated and English names, so the whole array falls back together —
    # the same rule I18nStore.subtree applies for the JS payload.
    def name_array(key, expected_length)
      names = I18nStore.subtree("red.js", locale: red_locale)[key]
      return names if names.is_a?(Array) && names.length == expected_length

      fallback = I18nStore.subtree("red.js", locale: I18nStore::DEFAULT_LOCALE)[key]
      fallback.is_a?(Array) ? fallback : []
    end

    # A 24-hour locale may legitimately translate these to "", which is why
    # this checks for a String rather than for presence.
    def meridian_for(time)
      meridian = I18nStore.subtree("red.js.meridian", locale: red_locale)
      value = time.hour >= 12 ? meridian[:pm] : meridian[:am]
      return value if value.is_a?(String)

      time.hour >= 12 ? "PM" : "AM"
    end
  end
end
