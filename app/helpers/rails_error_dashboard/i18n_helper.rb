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
    # red_js_t needs escape_javascript. In a request the controller mixes every
    # engine helper into one view context, so it happens to be there — but that
    # is incidental, and it is absent in a type: :helper spec or anywhere this
    # module is included on its own. Include it explicitly rather than depend on
    # the ambient context; the same fix P2-T11 applied to the T10 helpers.
    include ActionView::Helpers::JavaScriptHelper
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

    # Translate for interpolation into a JavaScript string literal.
    #
    # red_t html-escapes, which is right for page text and wrong here. The two
    # sinks in the layout's script blocks disagree about entities: showToast
    # and innerHTML decode &#39; back to an apostrophe, but textContent renders
    # it literally, so a French string would display "d&#39;accéder" on screen.
    #
    # escape_javascript is what the surrounding code already uses for flash
    # messages (`<%= j flash[:notice] %>`), and it is the correct escaping for
    # this position: it neutralizes quotes, backslashes and line terminators
    # that would break out of or truncate the literal, without touching
    # characters the sink will render.
    #
    # Values still pass through the same total lookup, so a missing key is
    # readable text rather than a raise inside a <script> block.
    #
    # @param key [String, Symbol] e.g. "red.ui_js.toast.copied"
    # @return [String] html_safe, escaped for a JS string literal
    def red_js_t(key, **options)
      escape_javascript(I18nStore.translate(key, locale: red_locale, **options)).html_safe
    rescue StandardError
      ""
    end

    # Pluralized variant of red_js_t, for counts written by JS.
    def red_js_tp(key, count:, **options)
      red_js_t(key, count: count, **options)
    end

    # The translation payload handed to the browser as window.RED_I18N.
    #
    # Deliberately NOT the whole dictionary. This ships inside every dashboard
    # page, so it carries only what JavaScript re-renders on the client: the
    # red.js.* subtree and the strftime patterns that formatDateTime() is
    # handed via data-format. Server-rendered strings already arrive as HTML
    # and must never be sent twice.
    #
    # Values are raw, not html-escaped. They are serialized as JSON by
    # js_safe_json — which neutralizes "</" against a </script> breakout — and
    # then consumed as JS strings, so ERB escaping here would render literal
    # &amp;amp; in the browser.
    #
    # @return [Hash] never nil, never raises. {} at worst.
    def red_js_translations
      locale = red_locale

      {
        "locale" => locale,
        "js" => I18nStore.subtree("red.js", locale: locale),
        "formats" => I18nStore.subtree("red.time.formats", locale: locale),
        # Not under red.js because the server renders it too — local_time_ago
        # wraps the same key. Sharing one key is the point: both sides then
        # put "ago" wherever the language wants it, rather than each guessing.
        "ago" => I18nStore.translate("red.time.ago", locale: locale)
      }
    rescue StandardError
      {}
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
