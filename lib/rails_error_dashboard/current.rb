module RailsErrorDashboard
  # Request-scoped state for the dashboard.
  #
  # Currently holds only the locale. ActiveSupport resets CurrentAttributes
  # between requests, but the dashboard does NOT rely on that alone — the
  # around_action in ApplicationController clears this explicitly in an
  # ensure block. Two reasons:
  #
  #   1. RED renders inside the host app's process, on Puma threads the host
  #      also uses. State that outlives its request is the shape behind both
  #      #143 and #148, where a value stranded on a recycled thread leaked
  #      into a later request.
  #   2. The reset is a framework guarantee we do not want to depend on for a
  #      safety property.
  #
  # NOTE: locale intentionally has NO default. A getter that coerced nil to
  # "en" would make restoration stamp "en" onto a thread that started clean —
  # the exact trap documented in ApplicationController#with_dashboard_locale
  # for Pagy. Callers resolve the default themselves via .locale_or_default.
  class Current < ActiveSupport::CurrentAttributes
    attribute :locale

    class << self
      # The locale the dashboard should render in, applying full precedence:
      #
      #   Current.locale            (set per request; later, the user's picker)
      #     -> config.dashboard_locale
      #       -> "en"
      #
      # Each candidate is validated against the locales RED actually ships, so
      # a configured locale we cannot serve degrades to English instead of
      # failing mid-render.
      #
      # @return [String] a locale RED ships. Never nil, never raises.
      def locale_or_default
        # to_s.strip rather than .presence — locale is a public attribute and
        # a later caller (the session-backed picker in Phase 5) could put any
        # object in it. Anything that is not a usable String falls through to
        # the configured value.
        candidate = locale.to_s.strip
        candidate = configured_locale.to_s.strip if candidate.empty?
        I18nStore.resolve(candidate)
      rescue StandardError
        I18nStore::DEFAULT_LOCALE
      end

      private

      def configured_locale
        RailsErrorDashboard.configuration&.dashboard_locale
      rescue StandardError
        nil
      end
    end
  end
end
