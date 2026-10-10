# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Wraps the host app's I18n.exception_handler so every missing translation
    # is counted, then hands the exception to the handler the app already had.
    #
    # WHY THE EXCEPTION HANDLER: it is the one place every miss passes
    # through. I18n.t calls it directly (i18n/lib/i18n.rb, handle_exception),
    # and the view helper calls it from missing_translation before rendering
    # the "translation missing" span (actionview translation_helper.rb). There
    # is no ActiveSupport::Notifications event for a miss, so subscribing, as
    # the deprecation tracker does, is not an option.
    #
    # WHAT IS NOT SEEN, by design: a lookup given a :default never misses, and
    # with raise_on_missing_translations (or `raise: true`) I18n raises before
    # reaching any handler -- that miss surfaces as an exception, which RED
    # captures as an error anyway.
    #
    # This is the one place RED touches global I18n state, which is why it is
    # opt-in (enable_missing_translation_tracking, default false) and why the
    # wrapper is transparent: it changes no return value, swallows no
    # exception the original would have raised, and uninstall! puts the
    # original back. RED's own dashboard strings never arrive here; I18nStore
    # resolves them in a private backend.
    class MissingTranslationHandler
      attr_reader :original

      # @param original [#call, Symbol] the handler being wrapped. I18n allows
      #   a Symbol naming a method on I18n itself; it is delegated the same way
      #   I18n.handle_exception would.
      def initialize(original)
        @original = original
      end

      # The I18n exception handler contract.
      def call(exception, locale, key, options)
        track(exception, locale, key, options) if exception.is_a?(::I18n::MissingTranslation)
        delegate(exception, locale, key, options)
      end

      class << self
        # Wrap the current global handler. Idempotent: a second install (code
        # reloading, a spec that installs twice) does not stack wrappers.
        # @return [MissingTranslationHandler]
        def install!
          current = ::I18n.exception_handler
          return current if current.is_a?(self)

          ::I18n.exception_handler = new(current)
        end

        # Put the wrapped handler back. A no-op when nothing is installed.
        def uninstall!
          current = ::I18n.exception_handler
          return unless current.is_a?(self)

          ::I18n.exception_handler = current.original
        end

        def installed?
          ::I18n.exception_handler.is_a?(self)
        end
      end

      private

      # Counting must never change what the host sees, so it is rescued on its
      # own and the exception is delegated whatever happened here.
      def track(exception, locale, key, options)
        # The full dotted key as I18n normalised it, scope included, locale
        # excluded: "users.show.greeting", not "en.users.show.greeting".
        scope = options.is_a?(Hash) ? options[:scope] : nil
        full_key = ::I18n.normalize_keys(nil, exception.key, scope).join(".")

        MissingTranslationTracker.record(locale: locale.to_s, key: full_key)
      rescue => e
        nil
      end

      def delegate(exception, locale, key, options)
        case original
        when Symbol
          ::I18n.send(original, exception, locale, key, options)
        else
          original.call(exception, locale, key, options)
        end
      end
    end
  end
end
