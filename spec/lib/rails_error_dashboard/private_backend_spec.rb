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
end
