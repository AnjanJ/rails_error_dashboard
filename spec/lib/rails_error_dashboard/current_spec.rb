# frozen_string_literal: true

require "rails_helper"

# Request-scoped locale state.
#
# The critical property is that locale has no default. A getter coercing nil
# to "en" would make the around_action's restore stamp "en" onto a thread that
# started clean — the trap documented in ApplicationController for Pagy, and
# the shape behind both #143 and #148.
RSpec.describe RailsErrorDashboard::Current do
  after do
    described_class.locale = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  describe ".locale" do
    it "is nil when unset" do
      expect(described_class.locale).to be_nil
    end

    it "does not coerce nil to a default" do
      described_class.locale = nil

      expect(described_class.locale).to be_nil
    end
  end

  describe ".locale_or_default" do
    it "uses the explicitly set locale when present" do
      described_class.locale = "en"

      expect(described_class.locale_or_default).to eq("en")
    end

    it "falls back to the configured dashboard locale when unset" do
      described_class.locale = nil
      RailsErrorDashboard.configuration.dashboard_locale = "en"

      expect(described_class.locale_or_default).to eq("en")
    end

    it "falls back to English when the configured locale is not shipped" do
      described_class.locale = nil
      RailsErrorDashboard.configuration.dashboard_locale = "zz"

      expect(described_class.locale_or_default).to eq("en")
    end

    it "falls back to English when the configured locale is blank" do
      described_class.locale = nil
      RailsErrorDashboard.configuration.dashboard_locale = ""

      expect(described_class.locale_or_default).to eq("en")
    end

    it "resolves a wrong-cased locale to a shipped one" do
      described_class.locale = "EN"

      expect(described_class.locale_or_default).to eq("en")
    end

    context "with hostile values" do
      [ 123, [], {}, :en, "  ", "fr-CA", "zz" ].each do |value|
        it "does not raise for #{value.inspect}" do
          described_class.locale = value

          expect { described_class.locale_or_default }.not_to raise_error
          expect(described_class.locale_or_default).to be_a(String)
        end
      end

      it "returns English when configuration itself raises" do
        described_class.locale = nil

        # Scoped to the assertion so the stub cannot bleed into the after hook,
        # which needs a working configuration to reset state.
        result = nil
        RSpec::Mocks.with_temporary_scope do
          allow(RailsErrorDashboard).to receive(:configuration).and_raise(StandardError)
          result = described_class.locale_or_default
        end

        expect(result).to eq("en")
      end
    end
  end

  describe "request isolation" do
    it "clears between CurrentAttributes resets" do
      described_class.locale = "en"

      described_class.reset

      expect(described_class.locale).to be_nil
    end
  end
end
