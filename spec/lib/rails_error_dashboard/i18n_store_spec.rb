# frozen_string_literal: true

require "rails_helper"

# RED translates through its own I18n backend rather than the host app's.
#
# The point is host-app safety: a host with raise_on_missing_translations,
# a short available_locales list, or a custom exception handler must not be
# able to break the error dashboard — the one page that has to work when
# everything else in the app is broken.
RSpec.describe RailsErrorDashboard::I18nStore do
  describe "host app isolation" do
    it "does not mutate the host's I18n configuration" do
      before_state = [
        I18n.load_path.dup,
        I18n.available_locales.dup,
        I18n.default_locale,
        I18n.backend
      ]

      described_class.translate("red.common.not_available")
      described_class.translate("red.time.ago", locale: :fr, duration: "3 hours")
      described_class.available_locales
      described_class.resolve("de")

      expect([ I18n.load_path, I18n.available_locales, I18n.default_locale, I18n.backend ])
        .to eq(before_state)
    end

    it "does not read the host's I18n.load_path" do
      # A key that exists only in the host's store must stay invisible to RED.
      I18n.backend.store_translations(:en, red: { host_injected_key: "FROM HOST" })

      expect(described_class.translate("red.host_injected_key")).not_to eq("FROM HOST")
    end

    it "renders when the host enforces a locale allowlist that excludes RED's" do
      original_enforce = I18n.enforce_available_locales
      original_available = I18n.available_locales

      begin
        I18n.available_locales = [ :ja ]
        I18n.enforce_available_locales = true

        expect(described_class.translate("red.common.not_available")).to eq("N/A")
      ensure
        I18n.available_locales = original_available
        I18n.enforce_available_locales = original_enforce
      end
    end

    # Both of these are about the backend's CONTENTS, not about a lookup
    # degrading gracefully. A host setting that quietly strips locales out of
    # RED's dictionary is worse than one that raises: every page renders
    # English and nothing anywhere says why.
    it "loads its own locale files even when the host allowlists other locales" do
      original = I18n.available_locales
      path = RailsErrorDashboard::Engine.root.join("config", "locales", "xh.yml")

      begin
        path.write("xh:\n  red:\n    common:\n      close: \"XH-CLOSE\"\n")
        # I18n::Backend::Simple#load_translations filters what it reads through
        # this global and silently drops the rest.
        I18n.available_locales = [ :en, :ja ]
        described_class.reset!

        expect(described_class.translate("red.common.close", locale: "xh")).to eq("XH-CLOSE")
      ensure
        path.delete if path.exist?
        I18n.available_locales = original
        described_class.reset!
      end
    end

    it "leaves the host's available_locales exactly as it found them" do
      original_explicit = I18n.config.instance_variable_get(:@available_locales)

      begin
        I18n.available_locales = [ :en, :ja ]
        # What the host observes before RED touches anything.
        expected = I18n.available_locales.dup

        described_class.reset!
        described_class.backend

        expect(I18n.available_locales).to eq(expected)
      ensure
        I18n.available_locales = original_explicit
        described_class.reset!
      end
    end

    it "never leaves the host with an empty allowlist" do
      # The failure mode being guarded: restoring a saved value that was really
      # "unset" as [] would give the host an allowlist excluding every locale,
      # breaking the HOST's own translations rather than RED's.
      before = I18n.available_locales.dup

      described_class.reset!
      described_class.backend

      expect(I18n.available_locales).not_to be_empty
      expect(I18n.available_locales).to eq(before)
    end

    it "does not absorb the host's load path into its own dictionary" do
      # load_translations does not mark the backend initialized, so the first
      # lookup would otherwise call init_translations and pull in every locale
      # file the host app and its gems have registered.
      described_class.reset!
      described_class.translate("red.common.close")

      expect(described_class.backend.send(:translations).keys).to eq(described_class.available_locales)
    end

    it "renders when the host raises on missing translations" do
      original_handler = I18n.exception_handler

      begin
        I18n.exception_handler = ->(exception, *_args) { raise exception.to_exception }

        expect(described_class.translate("red.common.not_available")).to eq("N/A")
        expect { described_class.translate("red.nope.not_here") }.not_to raise_error
      ensure
        I18n.exception_handler = original_handler
      end
    end
  end

  describe ".translate" do
    it "returns the translation for a key that exists" do
      expect(described_class.translate("red.common.not_available")).to eq("N/A")
    end

    it "interpolates named arguments" do
      expect(described_class.translate("red.time.ago", duration: "3 hours")).to eq("3 hours ago")
    end

    it "falls back to English for a locale that lacks the key" do
      expect(described_class.translate("red.common.not_available", locale: :fr)).to eq("N/A")
    end

    it "returns readable text rather than a missing-translation marker" do
      result = described_class.translate("red.nope.some_missing_key")

      expect(result).to eq("Some missing key")
      expect(result).not_to include("translation missing")
    end

    it "returns a subtree key as fallback text rather than a Hash" do
      # "red.time.formats" is a namespace, not a leaf. Rendering a Hash into a
      # view would be a caller bug; degrade instead of exploding.
      expect(described_class.translate("red.time.formats")).to be_a(String)
    end

    context "with hostile input" do
      [ nil, "", :"", "   ", 123, [], {} ].each do |bad_key|
        it "does not raise for key #{bad_key.inspect}" do
          expect { described_class.translate(bad_key) }.not_to raise_error
          expect(described_class.translate(bad_key)).to be_a(String)
        end
      end

      [ nil, "", "zz", "EN", :fr, 123, "fr-CA" ].each do |bad_locale|
        it "does not raise for locale #{bad_locale.inspect}" do
          expect { described_class.translate("red.common.not_available", locale: bad_locale) }
            .not_to raise_error
        end
      end

      it "does not raise when an interpolation argument is missing" do
        expect { described_class.translate("red.time.ago") }.not_to raise_error
      end

      it "does not raise when given an unexpected interpolation argument" do
        expect { described_class.translate("red.common.not_available", nonsense: "x") }
          .not_to raise_error
      end
    end

    context "when a locale supplies only the :other plural form" do
      # Real hazard for translated locales: English has one/other, but a
      # translator may supply only :other, and Simple#translate raises
      # I18n::InvalidPluralizationData when :count needs a form that is absent.
      # That must degrade to English, never 500 the dashboard.
      before do
        described_class.backend.store_translations(
          :xx, red: { plural_probe: { other: "%{count} things" } }
        )
      end

      it "does not raise when count needs a missing plural category" do
        expect { described_class.translate("red.plural_probe", locale: :xx, count: 1) }
          .not_to raise_error
      end
    end
  end

  describe ".available_locales" do
    it "derives locales from the files RED actually ships" do
      expect(described_class.available_locales).to include(:en)
    end

    it "returns symbols" do
      expect(described_class.available_locales).to all(be_a(Symbol))
    end
  end

  describe ".resolve" do
    it "returns a shipped locale unchanged" do
      expect(described_class.resolve("en")).to eq("en")
    end

    it "matches case-insensitively" do
      # "EN" passes a naive format check but misses a dictionary keyed by exact
      # filename — the same class of bug the Pagy resolver guards against.
      expect(described_class.resolve("EN")).to eq("en")
    end

    it "falls back to English for a locale RED does not ship" do
      expect(described_class.resolve("zz")).to eq("en")
    end

    [ nil, "", "   ", 123, [], {} ].each do |value|
      it "falls back to English for #{value.inspect}" do
        expect(described_class.resolve(value)).to eq("en")
      end
    end
  end

  describe ".available?" do
    it "is true for a shipped locale" do
      expect(described_class.available?("en")).to be(true)
    end

    it "is true regardless of case" do
      expect(described_class.available?("EN")).to be(true)
    end

    it "is false for a locale RED does not ship" do
      expect(described_class.available?("zz")).to be(false)
    end

    it "is false for blank input" do
      expect(described_class.available?(nil)).to be(false)
      expect(described_class.available?("")).to be(false)
    end
  end

  # .subtree exists because #translate deliberately treats a Hash result as a
  # miss. The JS payload needs the branch, so it gets its own total method
  # rather than a flag that would weaken #translate's contract.
  describe ".subtree" do
    it "returns a branch of the dictionary as a Hash" do
      result = described_class.subtree("red.time.formats")

      expect(result).to be_a(Hash)
      expect(result[:full]).to eq("%B %d, %Y %I:%M:%S %p")
    end

    it "returns an empty hash for a missing key rather than raising" do
      expect(described_class.subtree("red.nope.not_a_branch")).to eq({})
    end

    # The mirror of #translate's Hash rule: asking for a branch and getting a
    # leaf is a caller bug, and returning the string would break JSON shape.
    it "returns an empty hash for a leaf key" do
      expect(described_class.subtree("red.time.ago")).to eq({})
    end

    it "falls back to English for a locale it does not ship" do
      result = described_class.subtree("red.time.formats", locale: :fr)

      expect(result[:full]).to eq("%B %d, %Y %I:%M:%S %p")
    end

    it "is total for garbage input" do
      [ nil, "", :"", 42, [], {} ].each do |bad_key|
        expect { described_class.subtree(bad_key) }.not_to raise_error
        expect(described_class.subtree(bad_key)).to be_a(Hash)
      end
    end

    it "is total for a garbage locale" do
      [ nil, "", "zz", 42, [] ].each do |bad_locale|
        expect { described_class.subtree("red.js", locale: bad_locale) }.not_to raise_error
        expect(described_class.subtree("red.js", locale: bad_locale)).to be_a(Hash)
      end
    end
  end

  describe "translation loading" do
    it "loads translations once rather than on every lookup" do
      described_class.reset!
      # Prime the backend, then assert no further disk loads happen.
      described_class.translate("red.common.not_available")

      expect(described_class.backend).not_to receive(:load_translations)

      5.times { described_class.translate("red.common.not_available") }
    end

    it "returns the same backend instance across calls" do
      expect(described_class.backend).to equal(described_class.backend)
    end
  end
end
