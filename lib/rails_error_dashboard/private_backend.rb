# frozen_string_literal: true

require "i18n"

module RailsErrorDashboard
  # The backend behind I18nStore: a Backend::Simple that the host app's I18n
  # configuration cannot reach into.
  #
  # Backend::Simple is very nearly private already — it holds its own
  # translations hash and its own initialized flag. Two upstream behaviours
  # break that, and both act at LOAD time rather than lookup time, so neither
  # raises and neither leaves a trace. The dashboard simply renders English.
  # Both were found in P4-T3, by a fixture locale that kept resolving to
  # English; see tasks/i18n-sprint-plan.md.
  #
  # This class states the two fixes as invariants of RED's backend. The
  # previous implementation got the same result by clearing and restoring
  # I18n.available_locales around the load and by poking @initialized from
  # outside — correct, but it mutated a global that a concurrent thread could
  # observe mid-window. Nothing here touches global state.
  class PrivateBackend < ::I18n::Backend::Simple
    # DEFECT 1 — the host's allowlist must not decide what RED's dictionary
    # CONTAINS.
    #
    # Upstream store_translations opens with a guard that discards the data,
    # silently, returning it unstored, when all three of these hold:
    #
    #   1. I18n.enforce_available_locales           (the Rails DEFAULT)
    #   2. I18n.available_locales_initialized?      (a one-way latch, below)
    #   3. the locale is absent from the host's list
    #
    # Condition 2 is the fuse, and nothing can defuse it: it flips the first
    # time anything ASSIGNS to I18n.available_locales, and I18n exposes no way
    # to clear it. A host that configures locales at boot — or any gem that
    # touches the setting once — arms the filter for the life of the process.
    #
    # The effect is that a host with `config.i18n.available_locales = [:en, :ja]`
    # strips RED's de/fr/es/pt-BR out of RED's OWN private dictionary, and every
    # dashboard page renders English with nothing anywhere to say why.
    #
    # The guard is the first statement in the upstream method, so there is no
    # way to skip it via super and no supported hook to satisfy it — its three
    # inputs are all host globals. What follows it is four lines of public I18n
    # API, reproduced here without the guard.
    #
    # BECAUSE THIS RESTATES AN UPSTREAM BODY, it is pinned by
    # spec/lib/rails_error_dashboard/private_backend_spec.rb, which asserts the
    # upstream semantics this reproduces. If an i18n upgrade changes
    # store_translations, that spec fails loudly rather than this drifting
    # silently out of step.
    def store_translations(locale, data, options = ::I18n::EMPTY_HASH)
      locale = locale.to_sym
      translations[locale] ||= Concurrent::Hash.new
      data = ::I18n::Utils.deep_symbolize_keys(data) unless options.fetch(:skip_symbolize_keys, false)
      STORE_MUTEX.synchronize { ::I18n::Utils.deep_merge!(translations[locale], data) }
    end

    # DEFECT 2 — the host's load_path must not decide what RED's dictionary
    # CONTAINS either.
    #
    # Backend::Base#load_translations falls back to I18n.load_path when called
    # with no filenames, and upstream init_translations calls it exactly that
    # way. So any lookup against a backend that was never marked initialized
    # merges every locale file the host app and its gems have registered into
    # RED's dictionary — the precise coupling I18nStore exists to prevent. In
    # RED's own suite that meant all of Faker's locales; in a host app it means
    # a colliding key resolving by load order.
    #
    # Marking the backend initialized without reading anything makes the
    # explicit load_translations(*files) in I18nStore#build_backend the only
    # thing that ever populates it. Lookups are unaffected: upstream #lookup
    # and #available_locales call init_translations only `unless initialized?`.
    def init_translations
      @initialized = true
    end
    # Upstream declares init_translations protected. Keep it so: widening an
    # inherited method's visibility is a silent API change.
    protected :init_translations

    # DEFECT 3 — upstream's plural rule is English, so a locale with different
    # CLDR categories cannot be rendered at all.
    #
    # Backend::Base#pluralization_key is `count == 1 ? :one : :other` with a
    # :zero special case. That IS English (and de/fr/es/pt-BR are close enough
    # that nothing noticed). It is wrong for any language whose categories
    # differ, and it fails in the two opposite directions RED now has to serve:
    #
    #   ja, zh-CN  have `other` ALONE. At count 1 upstream asks for :one, the
    #              entry has no :one, and pluralize raises
    #              InvalidPluralizationData. I18nStore rescues that into the
    #              English fallback, so a fully translated Japanese string
    #              renders in ENGLISH for every count of 1 — silently.
    #   fr, es,    have `many`. Upstream never asks for it, so the category the
    #   pt-BR      locale is required to supply is dead weight.
    #
    # RED cannot depend on rails-i18n for real CLDR rules (invariant 7 — no new
    # runtime dependency), and does not need to: it ships a known, small set of
    # locales, and the categories each one uses are already declared in
    # bin/i18n-check. This table is the runtime half of that same statement.
    #
    # Only `other` is guaranteed. Every branch falls back to :other when the
    # category it wants is absent, so a partially-translated entry degrades to
    # a rendered string rather than to the English fallback.
    PLURAL_RULES = {
      # No grammatical number: one form covers every count.
      "ja" => ->(_count) { :other },
      "zh-CN" => ->(_count) { :other },
      # 0 and 1 both take the singular; millions take `many`.
      "fr" => ->(count) { count.abs < 2 ? :one : :other },
      # `many` is the CLDR category for large round numbers. RED's strings are
      # counts of errors and users, so the practical split is one/other; asking
      # for :many only when the entry actually supplies it keeps a correct
      # es/pt-BR file working either way.
      "es" => ->(count) { count == 1 ? :one : :other },
      "pt-BR" => ->(count) { count.abs < 2 ? :one : :other },
      # Russian, the first four-category locale. Unlike the Romance rules
      # above, `other` is NOT the fallback bucket here — CLDR assigns it to
      # fractional counts only, and every whole number lands in one/few/many.
      #
      # The %100 guards are the part that is easy to get wrong: 11 is `many`,
      # not `one`, and 12-14 are `many`, not `few`, even though 1 and 2-4 are.
      # A rule written only on %10 renders "11 ошибка" instead of "11 ошибок".
      "ru" => lambda { |count|
        return :other unless count.is_a?(Integer)

        i = count.abs
        mod10 = i % 10
        mod100 = i % 100

        return :one if mod10 == 1 && mod100 != 11
        return :few if (2..4).cover?(mod10) && !(12..14).cover?(mod100)

        :many
      }
    }.freeze
    private_constant :PLURAL_RULES

    # Overrides the hook rather than #pluralize, so upstream's
    # InvalidPluralizationData guard still fires for an entry that genuinely
    # lacks the category asked for — a missing form must stay loud, and
    # I18nStore's rescue must stay a safety net rather than the normal path.
    #
    # A locale absent from PLURAL_RULES keeps upstream's English behaviour,
    # which is the right default: de and en are English-shaped, and an unknown
    # locale is better served by the documented upstream rule than by a guess.
    def pluralization_key(entry, count)
      rule = PLURAL_RULES[@current_pluralization_locale.to_s]
      return super unless rule

      return :zero if count == 0 && entry.has_key?(:zero)

      key = rule.call(count)
      entry.has_key?(key) ? key : :other
    end

    # Upstream calls pluralization_key from #pluralize, which knows the locale;
    # the hook itself does not receive it. Capture it around the call rather
    # than reading I18n.locale, which is the HOST's current locale and need not
    # be the locale this lookup is for (I18nStore always passes locale:
    # explicitly, and jobs render several locales under one I18n.locale).
    def pluralize(locale, entry, count)
      previous = @current_pluralization_locale
      @current_pluralization_locale = locale
      super
    ensure
      @current_pluralization_locale = previous
    end

    # Upstream guards its own deep_merge! with a private class-level mutex
    # (Simple::Implementation::MUTEX). Reaching for that constant would couple
    # this to an internal name; RED holds its own, which is equivalent because
    # it guards writes to this backend's own translations hash.
    STORE_MUTEX = Mutex.new
    private_constant :STORE_MUTEX
  end
end
