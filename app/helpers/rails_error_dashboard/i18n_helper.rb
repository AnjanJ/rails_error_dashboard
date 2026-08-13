module RailsErrorDashboard
  # View-layer entry point for RED's translations.
  #
  # The helper is deliberately named red_t, not t. Two reasons:
  #
  #   1. Overriding `t` in an engine helper risks colliding with the host app's
  #      own helpers and with Rails' built-in translate, which has lazy-lookup
  #      behaviour ("t('.title')") that RED's private backend does not provide.
  #   2. An explicit name makes every translated site greppable — worth a lot
  #      when the remaining ~1,600 strings get extracted a page at a time.
  module I18nHelper
    # Translate a key in the current request's locale.
    #
    # Output is HTML-escaped unless the key ends in _html, matching Rails'
    # convention. Escaping happens here rather than in I18nStore because it is
    # a view concern — mailers' text parts and JS payloads must not be escaped.
    #
    # @param key [String, Symbol] e.g. "red.nav.errors"
    # @return [String] never nil, never raises
    def red_t(key, **options)
      value = I18nStore.translate(key, locale: red_locale, **options)

      if key.to_s.end_with?("_html")
        value.html_safe
      else
        ERB::Util.html_escape(value)
      end
    rescue StandardError
      ""
    end

    # Pluralized translation. Selects the plural form from +count+ using the
    # locale's CLDR rules, so it handles languages with more than English's
    # two forms.
    #
    # Always use this rather than a ternary on "s" — an English binary plural
    # is wrong in most languages, and several have no plural distinction at all.
    #
    # @param count [Integer] drives form selection and is available as %{count}
    def red_tp(key, count:, **options)
      red_t(key, count: count, **options)
    end

    # The locale this request renders in.
    # @return [String] a locale RED ships
    def red_locale
      Current.locale_or_default
    rescue StandardError
      I18nStore::DEFAULT_LOCALE
    end

    # A strftime pattern for one of ApplicationHelper#local_time's presets,
    # localized. Falls back to the English pattern for an unknown preset.
    #
    # Kept here rather than inline in the view so the Ruby fallback rendering
    # and the browser's data-format re-render always agree on the pattern.
    #
    # @param preset [Symbol, String] :full, :short, :date_only, :time_only, :datetime
    # @return [String] a raw strftime pattern — NOT html-escaped, since it is
    #   consumed by strftime and by the JS date formatter, not rendered as text
    def red_time_format(preset)
      key = "red.time.formats.#{preset}"
      pattern = I18nStore.translate(key, locale: red_locale)

      # A miss returns humanized key text, which would be a nonsense strftime
      # pattern. Detect it by the absence of any % directive and fall back.
      return pattern if pattern.include?("%")

      I18nStore.translate("red.time.formats.full", locale: I18nStore::DEFAULT_LOCALE)
    rescue StandardError
      "%B %d, %Y %I:%M:%S %p"
    end
  end
end
