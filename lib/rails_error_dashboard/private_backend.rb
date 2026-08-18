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

    # Upstream guards its own deep_merge! with a private class-level mutex
    # (Simple::Implementation::MUTEX). Reaching for that constant would couple
    # this to an internal name; RED holds its own, which is equivalent because
    # it guards writes to this backend's own translations hash.
    STORE_MUTEX = Mutex.new
    private_constant :STORE_MUTEX
  end
end
