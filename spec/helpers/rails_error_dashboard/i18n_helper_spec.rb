# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::I18nHelper, type: :helper do
  after do
    RailsErrorDashboard::Current.locale = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  describe "#red_t" do
    it "translates a key" do
      expect(helper.red_t("red.common.not_available")).to eq("N/A")
    end

    it "interpolates arguments" do
      expect(helper.red_t("red.time.ago", duration: "3 hours")).to eq("3 hours ago")
    end

    it "returns readable text for a missing key rather than raising" do
      expect(helper.red_t("red.nope.absent_key")).to eq("Absent key")
    end

    it "escapes HTML in translated values" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { xss_probe: "<script>alert(1)</script>" }
      )

      result = helper.red_t("red.xss_probe")

      expect(result).not_to include("<script>")
      expect(result).to include("&lt;script&gt;")
    end

    it "escapes HTML in interpolated values" do
      result = helper.red_t("red.time.ago", duration: "<script>alert(1)</script>")

      expect(result).not_to include("<script>")
    end

    it "marks _html-suffixed keys as safe" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { safe_probe_html: "<strong>bold</strong>" }
      )

      expect(helper.red_t("red.safe_probe_html")).to be_html_safe
    end

    [ nil, "", 123, [] ].each do |bad_key|
      it "does not raise for key #{bad_key.inspect}" do
        expect { helper.red_t(bad_key) }.not_to raise_error
      end
    end
  end

  describe "#red_tp" do
    before do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { count_probe: { one: "1 error", other: "%{count} errors" } }
      )
    end

    it "selects the singular form" do
      expect(helper.red_tp("red.count_probe", count: 1)).to eq("1 error")
    end

    it "selects the plural form" do
      expect(helper.red_tp("red.count_probe", count: 5)).to eq("5 errors")
    end

    it "uses the plural form for zero" do
      expect(helper.red_tp("red.count_probe", count: 0)).to eq("0 errors")
    end

    [ 0, 1, 2, 5, 11, 21, 100 ].each do |count|
      it "returns a String for count #{count}" do
        expect(helper.red_tp("red.count_probe", count: count)).to be_a(String)
      end
    end

    it "does not raise when the locale lacks the needed plural category" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { other_only_probe: { other: "%{count} things" } }
      )

      expect { helper.red_tp("red.other_only_probe", count: 1) }.not_to raise_error
    end
  end

  describe "#red_locale" do
    it "returns the configured locale" do
      expect(helper.red_locale).to eq("en")
    end

    it "prefers the request-scoped locale" do
      RailsErrorDashboard::Current.locale = "en"

      expect(helper.red_locale).to eq("en")
    end

    it "returns a shipped locale even when configuration is nonsense" do
      RailsErrorDashboard.configuration.dashboard_locale = "zz"

      expect(helper.red_locale).to eq("en")
    end
  end

  describe "#red_time_format" do
    it "returns the strftime pattern for a known preset" do
      expect(helper.red_time_format(:full)).to eq("%B %d, %Y %I:%M:%S %p")
    end

    it "returns a usable strftime pattern for every preset" do
      %i[full short date_only time_only datetime].each do |preset|
        pattern = helper.red_time_format(preset)

        expect(pattern).to include("%")
        expect { Time.now.utc.strftime(pattern) }.not_to raise_error
      end
    end

    it "falls back to a valid pattern for an unknown preset" do
      pattern = helper.red_time_format(:no_such_preset)

      expect(pattern).to include("%")
      expect { Time.now.utc.strftime(pattern) }.not_to raise_error
    end

    it "only uses directives the browser-side formatter supports" do
      # data-format is re-rendered by formatDateTime() in the layout, which
      # implements a fixed directive set. A pattern using anything else would
      # render literally in the browser.
      supported = %w[%Y %y %B %b %m %d %e %A %a %H %I %M %S %p %P]

      %i[full short date_only time_only datetime].each do |preset|
        directives = helper.red_time_format(preset).scan(/%[a-zA-Z]/)

        expect(directives - supported).to be_empty,
          "#{preset} uses directives the JS formatter cannot render: #{(directives - supported).inspect}"
      end
    end
  end
end
