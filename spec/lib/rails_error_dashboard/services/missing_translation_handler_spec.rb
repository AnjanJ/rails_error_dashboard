# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::MissingTranslationHandler do
  let(:tracker) { RailsErrorDashboard::Services::MissingTranslationTracker }

  # The global handler is shared by the whole suite: whatever this file does
  # to it must be undone, or every later spec runs under a leftover wrapper.
  around do |example|
    original = I18n.exception_handler
    RailsErrorDashboard.configuration.enable_missing_translation_tracking = true
    tracker.reset!
    example.run
  ensure
    I18n.exception_handler = original
    tracker.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".install!" do
    it "wraps the current handler and delegates to it" do
      seen = []
      I18n.exception_handler = ->(exception, locale, key, options) { seen << [ exception.class, locale, key ]; "host-handled" }

      described_class.install!
      result = I18n.t("users.show.greeting", locale: :en)

      expect(result).to eq("host-handled")
      expect(seen).to eq([ [ I18n::MissingTranslation, :en, "users.show.greeting" ] ])
    end

    it "is idempotent" do
      described_class.install!
      first = I18n.exception_handler
      described_class.install!

      expect(I18n.exception_handler).to equal(first)
      expect(first.original).not_to be_a(described_class)
    end

    it "wraps a Symbol handler the way I18n would call it" do
      I18n.singleton_class.class_eval do
        def red_spec_handler(exception, _locale, _key, _options)
          "symbol:#{exception.key}"
        end
      end
      I18n.exception_handler = :red_spec_handler

      described_class.install!

      expect(I18n.t("nope.nothing", locale: :en)).to eq("symbol:nope.nothing")
    ensure
      I18n.singleton_class.send(:remove_method, :red_spec_handler)
    end
  end

  describe ".uninstall!" do
    it "puts the original back" do
      original = I18n.exception_handler
      described_class.install!

      described_class.uninstall!

      expect(I18n.exception_handler).to equal(original)
      expect(described_class.installed?).to be(false)
    end
  end

  describe "counting" do
    before { described_class.install! }

    it "records every miss I18n.t reports, by locale and full key" do
      I18n.t("users.show.greeting", locale: :fr)
      I18n.t("users.show.greeting", locale: :fr)
      I18n.t(:greeting, scope: [ :users, :show ], locale: :de)

      counts = tracker.buffered_counts.transform_keys { |k| tracker.parse_key(k) }
      expect(counts[[ "fr", "users.show.greeting" ]][0]).to eq(2)
      expect(counts[[ "de", "users.show.greeting" ]][0]).to eq(1)
    end

    # Before Rails 8.1 the view helper never reaches the exception handler
    # (it looks up with a sentinel default and renders the span itself); 8.1
    # calls the handler from inside missing_translation. The prepended view
    # hook must count once on every version, never twice.
    it "records a miss the view helper reports, exactly once" do
      view = ActionView::Base.empty
      allow(ActionView::Base).to receive(:debug_missing_translation).and_return(true)

      html = I18n.with_locale(:en) { view.translate("users.show.greeting") }

      expect(html).to include("translation_missing")
      counts = tracker.buffered_counts.transform_keys { |k| tracker.parse_key(k) }
      expect(counts.keys).to eq([ [ "en", "users.show.greeting" ] ])
      expect(counts[[ "en", "users.show.greeting" ]][0]).to eq(1)
    end

    it "records a view miss with the explicit locale and scope options" do
      view = ActionView::Base.empty

      view.translate(:greeting, scope: [ :users, :show ], locale: :fr)

      expect(tracker.buffered_counts.keys.map { |k| tracker.parse_key(k) }).to eq([ [ "fr", "users.show.greeting" ] ])
    end

    it "clears the view-hook flag afterwards so a later I18n.t miss is counted" do
      ActionView::Base.empty.translate("users.show.greeting", locale: :en)
      I18n.t("users.show.greeting", locale: :en)

      key = tracker.buffered_counts.keys.find { |k| tracker.parse_key(k) == [ "en", "users.show.greeting" ] }
      expect(tracker.buffered_counts[key][0]).to eq(2)
    end

    it "does not count view misses once uninstalled, even though the hook stays prepended" do
      described_class.uninstall!

      ActionView::Base.empty.translate("users.show.greeting", locale: :en)

      expect(tracker.buffered_counts).to be_empty
      expect(ActionView::Helpers::TranslationHelper.ancestors).to include(described_class::ViewHelperHook)
    end

    it "does not count a lookup that had a default" do
      expect(I18n.t("users.show.greeting", default: "Hello", locale: :en)).to eq("Hello")

      expect(tracker.buffered_counts).to be_empty
    end

    it "does not count a translation that exists" do
      I18n.backend.store_translations(:en, red_spec: { present: "here" })

      expect(I18n.t("red_spec.present", locale: :en)).to eq("here")
      expect(tracker.buffered_counts).to be_empty
    end

    it "lets a raising lookup raise, exactly as before" do
      expect { I18n.t("users.show.greeting", raise: true, locale: :en) }
        .to raise_error(I18n::MissingTranslationData)
    end

    it "still delegates when counting itself fails" do
      allow(tracker).to receive(:record).and_raise(RuntimeError, "boom")

      expect(I18n.t("users.show.greeting", locale: :en)).to eq("Translation missing: en.users.show.greeting")
    end

    it "passes non-missing exceptions straight to the original handler" do
      exception = I18n::InvalidLocale.new(:xx)

      expect { I18n.exception_handler.call(exception, :xx, "k", {}) }.to raise_error(I18n::InvalidLocale)
      expect(tracker.buffered_counts).to be_empty
    end

    it "sees nothing from RED's own dashboard strings" do
      RailsErrorDashboard::I18nStore.translate("red.nav.this_key_does_not_exist", locale: "en")

      expect(tracker.buffered_counts).to be_empty
    end
  end
end
