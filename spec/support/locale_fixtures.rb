# frozen_string_literal: true

# Writes a temporary locale into config/locales so I18nStore loads it exactly
# the way it loads a shipped one.
#
# WHY THIS IS SHARED RATHER THAN INLINE IN EACH SPEC
#
# I18nStore memoizes its backend, and .reset! clears it globally. A fixture
# installed once in before(:all) can therefore be wiped by an unrelated spec's
# cleanup — and because a missing locale falls back to English rather than
# failing, that turns a broken assertion into a *passing* one. Installing per
# example, and probing a real key before each, makes that impossible to miss.
#
# Pick a tag no other spec uses as its negative case. In particular NOT "zz" —
# four i18n specs use that as their example of an unshipped locale, and making
# it available breaks them.
#
# NOTE ON WIRING: this is a plain module extended onto example groups, NOT an
# ActiveSupport::Concern whose class_methods get config.extend'ed. In that
# arrangement the `before` inside with_locale_fixture binds to RSpec's global
# config rather than to the calling group, so EVERY spec file's fixture
# installs for EVERY example in the suite. Two fixtures then race to write
# their own tag, and the loser silently renders English — which is how this
# helper spent a while reporting that an unrelated spec had cleared the
# backend.
module LocaleFixtures
  # @param tag [String] the locale tag, e.g. "xm"
  # @param probe [String] a key the fixture defines AND en.yml defines
  #   differently, used to prove the translations really loaded rather than
  #   just that the file is on disk
  # @param yaml [String] the file body, starting with "#{tag}:"
  def with_locale_fixture(tag, probe:, yaml:)
    before do
      path = RailsErrorDashboard::Engine.root.join("config", "locales", "#{tag}.yml")
      path.write(yaml)
      RailsErrorDashboard::I18nStore.reset!

      # Force the backend to build while the file is guaranteed on disk.
      # reset! only clears the memo; the rebuild is lazy, so without this the
      # first lookup can happen after another group's after-hook has deleted
      # its own fixture and reset again — and a locale that is on disk but not
      # in the backend resolves to English rather than failing.
      RailsErrorDashboard::I18nStore.backend

      # available? only reads FILENAMES, so it stays true even when the backend
      # holds no translations for the tag. Probe a real key instead.
      resolved = RailsErrorDashboard::I18nStore.translate(probe, locale: tag)
      english = RailsErrorDashboard::I18nStore.translate(probe, locale: "en")

      if resolved == english
        raise "locale fixture #{tag} did not load: #{probe} resolved to " \
              "#{resolved.inspect}, same as :en."
      end
    end

    after do
      path = RailsErrorDashboard::Engine.root.join("config", "locales", "#{tag}.yml")
      path.delete if path.exist?
      RailsErrorDashboard::I18nStore.reset!
      RailsErrorDashboard::Current.locale = nil
    end
  end
end

RSpec.configure do |config|
  config.extend LocaleFixtures
end
