# frozen_string_literal: true

module RailsErrorDashboard
  # Translation for code that is not a view.
  #
  # I18nHelper#red_t is a view helper: it html-escapes its output, because that
  # is what a template needs. Controllers and commands produce flash messages
  # and result strings that Rails escapes when the view renders them, so
  # escaping here would double-escape every apostrophe.
  #
  # Both paths resolve the locale the same way — Current.locale_or_default —
  # so a flash message set during a request renders in the same locale as the
  # page that shows it.
  #
  # Like everything else in the i18n path, these never raise. A controller
  # cannot be the place a translation lookup takes down the dashboard.
  module Translation
    # @param key [String, Symbol] e.g. "red.flash.issue.created"
    # @return [String] never nil, never raises, never html-escaped
    def red_t(key, **options)
      I18nStore.translate(key, locale: red_locale, **options)
    rescue StandardError
      ""
    end

    # Pluralized translation. Selects the form from +count+ using the locale's
    # CLDR rules rather than an English binary plural.
    def red_tp(key, count:, **options)
      red_t(key, count: count, **options)
    end

    # @return [String] a locale RED ships
    def red_locale
      Current.locale_or_default
    rescue StandardError
      I18nStore::DEFAULT_LOCALE
    end
  end
end
