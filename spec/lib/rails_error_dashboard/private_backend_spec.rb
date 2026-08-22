# frozen_string_literal: true

require "rails_helper"

# PrivateBackend removes two upstream behaviours that let the host app decide
# what RED's dictionary CONTAINS. Both act at load time and neither raises, so
# the only symptom is a dashboard rendering English — indistinguishable from a
# locale that simply is not translated yet.
#
# The specs in "the upstream behaviour it exists to remove" are PINS, not tests
# of RED. They assert what a stock Backend::Simple does. If an i18n upgrade
# changes store_translations or init_translations, they fail here and name the
# reason, rather than PrivateBackend drifting silently out of step with a body
# it partially restates.
RSpec.describe RailsErrorDashboard::PrivateBackend do
  # Force the exact trap: enforcement on, the availability latch tripped, and a
  # host allowlist that excludes the locale being stored.
  def with_host_allowlist(locales)
    original_enforce = I18n.enforce_available_locales
    original_available = I18n.available_locales
    I18n.available_locales = locales
    I18n.enforce_available_locales = true
    yield
  ensure
    I18n.available_locales = original_available
    I18n.enforce_available_locales = original_enforce
  end

  describe "the upstream behaviour it exists to remove" do
    it "pins that Backend::Simple drops translations for a locale off the host's allowlist" do
      stock = I18n::Backend::Simple.new

      with_host_allowlist([ :zu ]) do
        expect(I18n.available_locales_initialized?).to be(true),
          "the availability latch must be tripped for this pin to mean anything"

        stock.store_translations(:xh, red: { pinned: "STORED" })

        expect(stock.send(:translations)).not_to have_key(:xh),
          "upstream store_translations no longer filters by the host allowlist — " \
          "PrivateBackend#store_translations may no longer need to restate its body"
      end
    end

    it "pins that Backend::Simple absorbs the host's load_path on first lookup" do
      stock = I18n::Backend::Simple.new
      stock.store_translations(:en, red: { pinned: "STORED" })

      # Not initialized by store_translations, so the first lookup inits — and
      # upstream init_translations calls load_translations with no arguments,
      # which defaults to I18n.load_path.
      expect(stock.initialized?).to be(false),
        "upstream store_translations now marks the backend initialized — " \
        "PrivateBackend#init_translations may no longer be needed"

      stock.translate(:en, "red.pinned")

      expect(stock.send(:translations).keys).to include(*I18n.backend.send(:translations).keys),
        "upstream init_translations no longer reads I18n.load_path — " \
        "PrivateBackend#init_translations may no longer be needed"
    end

    it "pins the option that suppresses key symbolization" do
      # store_translations restates this branch; if upstream renames or drops
      # the option, the restatement is wrong.
      stock = I18n::Backend::Simple.new
      stock.store_translations(:en, { "red" => { "raw" => "R" } }, skip_symbolize_keys: true)

      expect(stock.send(:translations)[:en].keys).to include("red")
    end
  end

  describe "#store_translations" do
    it "stores a locale the host's allowlist excludes" do
      backend = described_class.new

      with_host_allowlist([ :zu ]) do
        backend.store_translations(:xh, red: { common: { close: "XH-CLOSE" } })

        expect(backend.translate(:xh, "red.common.close")).to eq("XH-CLOSE")
      end
    end

    it "leaves the host's I18n configuration untouched while storing" do
      backend = described_class.new

      with_host_allowlist([ :zu ]) do
        before = [ I18n.available_locales.dup, I18n.enforce_available_locales, I18n.load_path.dup ]

        backend.store_translations(:xh, red: { common: { close: "XH-CLOSE" } })

        expect([ I18n.available_locales, I18n.enforce_available_locales, I18n.load_path ]).to eq(before)
      end
    end

    it "symbolizes string keys the way upstream does" do
      backend = described_class.new
      backend.store_translations(:en, { "red" => { "deep" => { "key" => "V" } } })

      expect(backend.translate(:en, "red.deep.key")).to eq("V")
    end

    it "honours skip_symbolize_keys" do
      backend = described_class.new
      backend.store_translations(:en, { "red" => { "raw" => "R" } }, skip_symbolize_keys: true)

      expect(backend.send(:translations)[:en].keys).to include("red")
    end

    it "deep-merges rather than replacing an existing branch" do
      backend = described_class.new
      backend.store_translations(:en, red: { a: "A", nested: { x: "X" } })
      backend.store_translations(:en, red: { b: "B", nested: { y: "Y" } })

      expect(backend.translate(:en, "red.a")).to eq("A")
      expect(backend.translate(:en, "red.b")).to eq("B")
      expect(backend.translate(:en, "red.nested.x")).to eq("X")
      expect(backend.translate(:en, "red.nested.y")).to eq("Y")
    end
  end

  describe "#init_translations" do
    it "does not read the host's load_path" do
      backend = described_class.new
      backend.store_translations(:en, red: { only_key: "MINE" })

      backend.translate(:en, "red.only_key")

      expect(backend.send(:translations).keys).to eq([ :en ])
    end

    it "reports the backend as initialized without loading anything" do
      backend = described_class.new

      expect(backend.initialized?).to be(false)
      backend.send(:init_translations)

      expect(backend.initialized?).to be(true)
      expect(backend.send(:translations)).to be_empty
    end

    it "stays protected, as upstream declares it" do
      expect(described_class.protected_instance_methods).to include(:init_translations)
    end
  end

  # Upstream's plural rule is English: `count == 1 ? :one : :other`. That is
  # wrong in BOTH directions for the locales RED ships, and the ja direction is
  # silent — I18nStore rescues InvalidPluralizationData into the English
  # fallback, so a fully translated Japanese string renders in English at every
  # count of 1 rather than raising anywhere a spec would notice.
  describe "#pluralization_key" do
    def backend_with(locale, entry)
      described_class.new.tap do |backend|
        backend.store_translations(locale, red: { items: entry })
      end
    end

    # The pin: this is what a STOCK backend does, and why the override exists.
    it "pins that upstream raises for an other-only locale at count 1" do
      stock = I18n::Backend::Simple.new
      stock.store_translations(:ja, red: { items: { other: "%{count}件" } })

      expect { stock.translate(:ja, "red.items", count: 1) }
        .to raise_error(I18n::InvalidPluralizationData)
    end

    context "a locale whose CLDR rules give it `other` alone" do
      it "renders at count 1 rather than falling back to English" do
        backend = backend_with(:ja, { other: "%{count}件" })

        expect(backend.translate(:ja, "red.items", count: 1)).to eq("1件")
      end

      it "renders at every other count too" do
        backend = backend_with(:ja, { other: "%{count}件" })

        expect([ 0, 2, 11 ].map { |n| backend.translate(:ja, "red.items", count: n) })
          .to eq([ "0件", "2件", "11件" ])
      end
    end

    # Russian: one/few/many/other, the first four-category locale RED ships.
    # `other` here is NOT the catch-all it is in English — CLDR reserves it for
    # fractions, and every whole number lands in one/few/many.
    context "a locale whose CLDR rules give it four categories" do
      def russian_backend
        backend_with(:ru, {
          one: "%{count} час",
          few: "%{count} часа",
          many: "%{count} часов",
          other: "%{count} часа"
        })
      end

      it "selects `one` for counts ending in 1, except 11" do
        backend = russian_backend

        expect([ 1, 21, 101 ].map { |n| backend.translate(:ru, "red.items", count: n) })
          .to eq([ "1 час", "21 час", "101 час" ])
      end

      it "selects `few` for counts ending in 2-4, except 12-14" do
        backend = russian_backend

        expect([ 2, 4, 22 ].map { |n| backend.translate(:ru, "red.items", count: n) })
          .to eq([ "2 часа", "4 часа", "22 часа" ])
      end

      it "selects `many` for 0, 5-9 and the 11-14 band" do
        backend = russian_backend

        expect([ 0, 5, 11, 12, 14, 25 ].map { |n| backend.translate(:ru, "red.items", count: n) })
          .to eq([ "0 часов", "5 часов", "11 часов", "12 часов", "14 часов", "25 часов" ])
      end

      # The single most likely mistake when adding a Slavic locale: writing the
      # rule on %10 alone. 11 and 111 both end in 1 but take `many`.
      it "does not mistake 11 or 111 for the singular" do
        backend = russian_backend

        expect(backend.translate(:ru, "red.items", count: 11)).to eq("11 часов")
        expect(backend.translate(:ru, "red.items", count: 111)).to eq("111 часов")
      end
    end

    # uk and pl are also four-category, and this is the trap: they are NOT the
    # same rule as ru or as each other. Ukrainian matches Russian's integer
    # rule; POLISH DOES NOT — Polish `one` is exactly 1, so 21 and 101 take
    # `many` where uk/ru take `one`. Nothing structural catches a rule copied
    # from the wrong Slavic language: bin/i18n-check validates the FILE, and
    # both files have the identical four categories. Only selection shows it.
    context "two four-category locales whose rules differ from each other" do
      def ukrainian_backend
        backend_with(:uk, {
          one: "%{count} година",
          few: "%{count} години",
          many: "%{count} годин",
          other: "%{count} години"
        })
      end

      def polish_backend
        backend_with(:pl, {
          one: "%{count} godzina",
          few: "%{count} godziny",
          many: "%{count} godzin",
          other: "%{count} godziny"
        })
      end

      it "gives Ukrainian `one` for 1, 21 and 101, like Russian" do
        backend = ukrainian_backend

        expect([ 1, 21, 101 ].map { |n| backend.translate(:uk, "red.items", count: n) })
          .to eq([ "1 година", "21 година", "101 година" ])
      end

      it "gives Ukrainian `few` for 2-4 and `many` for the 11-14 band" do
        backend = ukrainian_backend

        expect([ 2, 4, 22 ].map { |n| backend.translate(:uk, "red.items", count: n) })
          .to eq([ "2 години", "4 години", "22 години" ])
        expect([ 0, 5, 11, 12, 14, 111 ].map { |n| backend.translate(:uk, "red.items", count: n) })
          .to eq([ "0 годин", "5 годин", "11 годин", "12 годин", "14 годин", "111 годин" ])
      end

      # The divergence, pinned on its own. Polish reserves `one` for exactly 1.
      it "gives Polish `one` for 1 ALONE — 21 and 101 are `many`" do
        backend = polish_backend

        expect(backend.translate(:pl, "red.items", count: 1)).to eq("1 godzina")
        expect(backend.translate(:pl, "red.items", count: 21)).to eq("21 godzin")
        expect(backend.translate(:pl, "red.items", count: 101)).to eq("101 godzin")
      end

      it "still gives Polish `few` for 2-4 outside the 12-14 band" do
        backend = polish_backend

        expect([ 2, 4, 22 ].map { |n| backend.translate(:pl, "red.items", count: n) })
          .to eq([ "2 godziny", "4 godziny", "22 godziny" ])
        expect([ 12, 14 ].map { |n| backend.translate(:pl, "red.items", count: n) })
          .to eq([ "12 godzin", "14 godzin" ])
      end

      # Stated as a direct comparison so a future edit that aliases one rule to
      # the other fails here rather than in a translator's bug report.
      it "disagrees between uk and pl at exactly the counts CLDR says it should" do
        uk = ukrainian_backend
        pl = polish_backend

        [ 21, 101 ].each do |n|
          expect(uk.translate(:uk, "red.items", count: n)).to include("година")
          expect(pl.translate(:pl, "red.items", count: n)).to include("godzin")
          expect(pl.translate(:pl, "red.items", count: n)).not_to include("godzina")
        end
      end
    end

    context "a locale shaped like English" do
      it "still selects one and other, unchanged" do
        backend = backend_with(:de, { one: "1 Fehler", other: "%{count} Fehler" })

        expect([ 1, 2 ].map { |n| backend.translate(:de, "red.items", count: n) })
          .to eq([ "1 Fehler", "2 Fehler" ])
      end

      it "leaves a locale absent from the table on upstream behaviour" do
        backend = backend_with(:xx, { one: "1", other: "many" })

        expect([ 1, 2 ].map { |n| backend.translate(:xx, "red.items", count: n) })
          .to eq([ "1", "many" ])
      end
    end

    it "honours an explicit zero form, as upstream does" do
      backend = backend_with(:ja, { zero: "なし", other: "%{count}件" })

      expect(backend.translate(:ja, "red.items", count: 0)).to eq("なし")
    end

    # The rule is chosen per LOOKUP locale, not from I18n.locale. A job renders
    # several locales under one host I18n.locale, so reading the global would
    # apply Japanese's rule to a German string.
    it "uses the locale being looked up, not the host's I18n.locale" do
      backend = described_class.new
      backend.store_translations(:ja, red: { items: { other: "%{count}件" } })
      backend.store_translations(:de, red: { items: { one: "1 Fehler", other: "%{count} Fehler" } })

      I18n.with_locale(:ja) do
        expect(backend.translate(:de, "red.items", count: 1)).to eq("1 Fehler")
      end
    end

    it "falls back to other when the rule asks for a category the entry lacks" do
      backend = backend_with(:fr, { other: "%{count} erreurs" })

      expect(backend.translate(:fr, "red.items", count: 1)).to eq("1 erreurs")
    end
  end
end
