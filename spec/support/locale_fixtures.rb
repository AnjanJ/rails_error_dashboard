# frozen_string_literal: true

# Writes a temporary locale into config/locales so I18nStore loads it exactly
# the way it loads a shipped one.
#
# WHY THIS IS SHARED RATHER THAN INLINE IN EACH SPEC
#
# I18nStore memoizes its backend, and .reset! clears it globally. Two specs
# that each write a fixture locale in before(:all) and clean up in after(:all)
# will corrupt each other under random ordering: spec B's cleanup reset can
# land between spec A's setup and A's examples, and A then renders English
# while claiming to test a translation. That is a silent pass-into-wrong-state,
# not a loud failure, which makes it worth centralizing.
#
# with_locale_fixture installs the file and resets around EACH example, so no
# other spec's cleanup can strand it.
#
# Pick a tag no other spec uses as its negative case. In particular NOT "zz" —
# four i18n specs use that as their example of an unshipped locale, and making
# it available breaks them.
module LocaleFixtures
  extend ActiveSupport::Concern

  class_methods do
    # @param tag [String] the locale tag, e.g. "xm"
    # @param yaml [String] the file body, starting with "#{tag}:"
    def with_locale_fixture(tag, yaml)
      before do
        path = RailsErrorDashboard::Engine.root.join("config", "locales", "#{tag}.yml")
        path.write(yaml)
        RailsErrorDashboard::I18nStore.reset!

        # Fail loudly rather than silently rendering English if the write did
        # not take effect — the bug this whole helper exists to prevent.
        unless RailsErrorDashboard::I18nStore.available?(tag)
          raise "locale fixture #{tag} was not picked up from #{path}"
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
end

RSpec.configure do |config|
  config.include LocaleFixtures
  config.extend LocaleFixtures::ClassMethods
end
