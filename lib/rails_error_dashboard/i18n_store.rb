require "rails_error_dashboard/private_backend"

module RailsErrorDashboard
  # RED's own translation store, deliberately isolated from the host app's I18n.
  #
  # WHY A PRIVATE BACKEND INSTEAD OF THE USUAL ENGINE LOAD PATH
  #
  # The conventional way to translate a Rails engine is to append
  # config/locales to I18n.load_path and namespace the keys. That shares the
  # host's backend, and sharing it hands the host three ways to break the
  # dashboard:
  #
  #   1. config.i18n.raise_on_missing_translations = true turns any key we
  #      forgot into a 500 — on the error dashboard, the one page that has to
  #      work when everything else is broken.
  #   2. enforce_available_locales with a short available_locales list raises
  #      I18n::InvalidLocale as soon as RED asks for its own locale.
  #   3. A custom exception_handler can raise on anything it likes.
  #
  # RED's locale is also deliberately independent of the host's — that is the
  # whole point of issue #148. Sharing a backend would re-create the coupling
  # that bug was about.
  #
  # The trade-off: hosts cannot override RED's strings with their own locale
  # files. That is the right default for a self-hosted ops tool, and it can be
  # relaxed later without breaking anything.
  #
  # NOTHING IN HERE MAY RAISE. Every public method is total: it returns a
  # String for any input, including garbage. See #translate.
  module I18nStore
    DEFAULT_LOCALE = "en".freeze

    # Raw backend lookups signal a miss by throwing :exception rather than
    # returning — I18n.translate is what normally catches it. We call the
    # backend directly, so we catch it ourselves.
    MISSING = Object.new.freeze
    private_constant :MISSING

    class << self
      # Translate +key+ in +locale+, falling back to English, then to a
      # readable last resort derived from the key itself.
      #
      # @param key [String, Symbol] dot-separated key, e.g. "red.nav.errors"
      # @param locale [String, Symbol] target locale
      # @return [String] always a String — never nil, never a raise
      def translate(key, locale: DEFAULT_LOCALE, **options)
        return "" if key.nil? || key.to_s.empty?

        resolved = lookup(key, locale, options)
        return resolved unless resolved.equal?(MISSING)

        unless locale.to_s == DEFAULT_LOCALE
          fallback = lookup(key, DEFAULT_LOCALE, options)
          return fallback unless fallback.equal?(MISSING)
        end

        humanized_key(key)
      rescue StandardError
        # Truly last resort. A translation lookup must never be the reason a
        # dashboard page fails to render.
        humanized_key(key)
      end
      alias_method :t, :translate

      # Fetch a whole branch of the dictionary as a Hash, for callers that need
      # the tree rather than one leaf — the JS payload is the only one today.
      #
      # #translate deliberately treats a Hash result as a miss: a key resolving
      # to a subtree instead of a leaf is a caller bug when you asked for text.
      # Here it is the point, so this is a separate method rather than a flag on
      # #translate.
      #
      # Falls back to English as a whole branch, not key by key. A partially
      # translated locale returning a half-English tree would be harder to
      # debug than one that is cleanly English until it is finished.
      #
      # @param key [String, Symbol] dot-separated key, e.g. "red.js"
      # @return [Hash] deep-frozen dup, or {} for a miss. Never nil, never raises.
      def subtree(key, locale: DEFAULT_LOCALE)
        return {} if key.nil? || key.to_s.empty?

        resolved = lookup_subtree(key, locale)
        return resolved unless resolved.equal?(MISSING)

        unless locale.to_s == DEFAULT_LOCALE
          fallback = lookup_subtree(key, DEFAULT_LOCALE)
          return fallback unless fallback.equal?(MISSING)
        end

        {}
      rescue StandardError
        {}
      end

      # Locales RED ships, derived from the files actually present.
      # @return [Array<Symbol>]
      def available_locales
        @available_locales ||= locale_files.map { |path| File.basename(path, ".yml").to_sym }.sort
      end

      # Resolve an arbitrary value to a locale RED can actually serve.
      # Matches case-insensitively ("EN" -> :en) because a wrong-cased tag that
      # passes a format check but misses the dictionary is a mid-render failure.
      #
      # @return [String] a locale RED ships, or "en"
      def resolve(value)
        candidate = value.to_s.strip
        return DEFAULT_LOCALE if candidate.empty?

        match = available_locales.find { |locale| locale.to_s.casecmp?(candidate) }
        match ? match.to_s : DEFAULT_LOCALE
      rescue StandardError
        DEFAULT_LOCALE
      end

      # @return [Boolean] whether RED ships this locale
      #
      # Compares case-insensitively rather than against a downcased copy —
      # "pt-BR" is a real locale filename and downcasing it would report a
      # locale we ship as unavailable.
      def available?(value)
        candidate = value.to_s.strip
        return false if candidate.empty?

        available_locales.any? { |locale| locale.to_s.casecmp?(candidate) }
      rescue StandardError
        false
      end

      # Double-checked locking. The fast path reads a fully-built backend; the
      # slow path builds it under the mutex. build_backend assigns only after
      # load_translations returns, so no thread can observe a half-loaded
      # backend through @backend.
      def backend
        cached = @backend
        return cached if cached

        load_mutex.synchronize do
          @backend ||= build_backend
        end
      end

      # Test seam. Clears memoized state so specs can reload from disk.
      def reset!
        load_mutex.synchronize do
          @backend = nil
          @available_locales = nil
        end
      end

      private

      # Returns the translated String, or MISSING. Never raises, never throws.
      def lookup(key, locale, options)
        result = catch(:exception) do
          backend.translate(locale.to_s.to_sym, key.to_s, **options)
        end

        # A miss throws :exception carrying an I18n::MissingTranslation.
        return MISSING if result.is_a?(::I18n::MissingTranslation)
        return MISSING if result.nil?

        # A key that resolves to a subtree rather than a leaf is a caller bug,
        # not something to render.
        return MISSING if result.is_a?(Hash)

        result.to_s
      rescue ::I18n::InvalidPluralizationData
        # A locale supplying only :other while :count is 1 (or missing a plural
        # category the count needs). Real risk for translated locales — English
        # has one/other, but not every language's forms line up. Fall through so
        # the caller gets English rather than a 500.
        MISSING
      rescue StandardError
        MISSING
      end

      # Returns a Hash for a subtree key, or MISSING. Never raises, never throws.
      def lookup_subtree(key, locale)
        result = catch(:exception) do
          backend.translate(locale.to_s.to_sym, key.to_s)
        end

        return MISSING unless result.is_a?(Hash)

        result
      rescue StandardError
        MISSING
      end

      # The backend is a PrivateBackend, not a bare Backend::Simple: two
      # upstream load-time behaviours let the host app decide what RED's
      # dictionary CONTAINS, and both are fixed there as invariants rather than
      # worked around here. See private_backend.rb for the mechanism — the
      # short version is that a host allowlist could strip RED's own locales
      # out of RED's own dictionary, and the first lookup could merge the
      # host's entire load_path in. Neither raises; both just render English.
      #
      # Found in P4-T3 by a spec fixture that kept resolving to English.
      def build_backend
        PrivateBackend.new.tap do |backend|
          files = locale_files
          backend.load_translations(*files) if files.any?
        end
      end

      def locale_files
        Dir[File.join(locales_path, "*.yml")].sort
      end

      def locales_path
        File.expand_path("../../config/locales", __dir__)
      end

      # "red.nav.error_logs" -> "Error logs". Readable, and never the string
      # "translation missing", which must never reach a user's screen.
      def humanized_key(key)
        segment = key.to_s.split(".").last.to_s
        return "" if segment.empty?

        segment.tr("_", " ").capitalize
      end

      def load_mutex
        @load_mutex ||= Mutex.new
      end
    end
  end
end
