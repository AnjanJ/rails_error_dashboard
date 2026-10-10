# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Wraps the host app's I18n.exception_handler so every missing translation
    # is counted, then hands the exception to the handler the app already had.
    #
    # WHY THE EXCEPTION HANDLER: I18n.t calls it for every miss
    # (i18n/lib/i18n.rb, handle_exception). There is no
    # ActiveSupport::Notifications event for a miss, so subscribing, as the
    # deprecation tracker does, is not an option.
    #
    # WHY ALSO A VIEW-HELPER HOOK: the view helper t() does NOT go through
    # the exception handler before Rails 8.1. It looks the key up with a
    # sentinel default (so I18n never misses) and renders the "translation
    # missing" span from its own missing_translation method; only 8.1 added
    # an exception_handler call there. Templates are where most misses live,
    # so ViewHelperHook is prepended onto ActionView's TranslationHelper and
    # counts in missing_translation itself. A thread flag set around super
    # keeps the handler from counting the same miss a second time on 8.1.
    #
    # WHAT IS NOT SEEN, by design: a lookup given a :default never misses, and
    # with raise_on_missing_translations (or `raise: true`) I18n raises before
    # reaching any handler -- that miss surfaces as an exception, which RED
    # captures as an error anyway.
    #
    # These are the only places RED touches global I18n and ActionView state,
    # which is why they are opt-in (enable_missing_translation_tracking,
    # default false) and transparent: no return value changes, no exception
    # the original would have raised is swallowed, and uninstall! puts the
    # original handler back (the view hook stays prepended -- Ruby cannot
    # un-prepend -- but does nothing while the handler is not installed).
    # RED's own dashboard strings never arrive here; I18nStore resolves them
    # in a private backend.
    class MissingTranslationHandler
      # Set by ViewHelperHook around super so a Rails 8.1+ missing_translation,
      # which calls the exception handler itself, is counted once, not twice.
      VIEW_HOOK_FLAG = :red_missing_translation_in_view_hook

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

      # Prepended onto ActionView::Helpers::TranslationHelper: counts the miss
      # the view helper is about to render as "translation missing".
      module ViewHelperHook
        private

        def missing_translation(key, options)
          if MissingTranslationHandler.installed?
            MissingTranslationHandler.record_view_miss(key, options)
            Thread.current.thread_variable_set(MissingTranslationHandler::VIEW_HOOK_FLAG, true)
          end
          super
        ensure
          Thread.current.thread_variable_set(MissingTranslationHandler::VIEW_HOOK_FLAG, nil)
        end
      end

      class << self
        # Wrap the current global handler and hook the view helper. Idempotent:
        # a second install (code reloading, a spec that installs twice) does
        # not stack wrappers.
        # @return [MissingTranslationHandler]
        def install!
          install_view_hook!

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

        # Count a miss the view helper reported. Never raises.
        def record_view_miss(key, options)
          options = {} unless options.is_a?(Hash)
          locale = options[:locale] || ::I18n.locale
          full_key = ::I18n.normalize_keys(nil, key, options[:scope]).join(".")

          MissingTranslationTracker.record(locale: locale.to_s, key: full_key)
        rescue => e
          nil
        end

        private

        def install_view_hook!
          return unless defined?(::ActionView::Helpers::TranslationHelper)

          helper = ::ActionView::Helpers::TranslationHelper
          helper.prepend(ViewHelperHook) unless helper.ancestors.include?(ViewHelperHook)
        rescue => e
          RailsErrorDashboard::Logger.debug(
            "[RailsErrorDashboard] MissingTranslationHandler view hook not installed: #{e.class} - #{e.message}"
          )
          nil
        end
      end

      private

      # Counting must never change what the host sees, so it is rescued on its
      # own and the exception is delegated whatever happened here.
      def track(exception, locale, key, options)
        # The view hook already counted this one (Rails 8.1+ calls the
        # handler from inside missing_translation).
        return if Thread.current.thread_variable_get(VIEW_HOOK_FLAG)

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
