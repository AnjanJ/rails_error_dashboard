# frozen_string_literal: true

require "rails_helper"

# The view helpers that returned English strings (P2-T10). The risk here is not
# the extraction — it is the boundary. These helpers sit next to brand names,
# machine identifiers and diagnostic output, and only the ordinary words move.
RSpec.describe "Helper translations", type: :helper do
  after do
    RailsErrorDashboard::Current.locale = nil
  end

  describe RailsErrorDashboard::BacktraceHelper do
    # These label where a frame came from. The backtrace content itself is
    # diagnostic output and is never translated.
    it "translates every frame category" do
      expect(helper.frame_category_name(:app)).to eq("Your Code")
      expect(helper.frame_category_name(:gem)).to eq("Gem")
      expect(helper.frame_category_name(:framework)).to eq("Rails Framework")
      expect(helper.frame_category_name(:ruby_core)).to eq("Ruby Core")
    end

    it "falls back to the unknown label for an unrecognized category" do
      expect(helper.frame_category_name(:something_else)).to eq("Unknown")
      expect(helper.frame_category_name(nil)).to eq("Unknown")
    end
  end

  describe RailsErrorDashboard::OverviewHelper do
    it "translates every trend direction" do
      expect(helper.trend_text(:increasing)).to eq("Increasing")
      expect(helper.trend_text(:decreasing)).to eq("Decreasing")
      expect(helper.trend_text(:stable)).to eq("Stable")
    end

    # The English original read an unrecognized direction as stable.
    it "reads an unrecognized direction as stable" do
      expect(helper.trend_text(nil)).to eq("Stable")
      expect(helper.trend_text(:sideways)).to eq("Stable")
    end

    # The emoji is part of the English rendering and lives in the key.
    it "translates the health status including its emoji" do
      expect(helper.health_status_text(:healthy)).to eq("✅ Healthy")
      expect(helper.health_status_text(:warning)).to eq("⚠️ Warning")
      expect(helper.health_status_text(:critical)).to eq("🔴 Critical")
    end

    # These keys are deliberately separate from the platform_comparison page's
    # health_card keys, which render the same states without emoji.
    it "does not collapse into the platform comparison health card keys" do
      card = RailsErrorDashboard::I18nStore.translate(
        "red.analytics.platform_comparison.health_card.healthy", locale: "en"
      )

      expect(card).to eq("Healthy")
      expect(helper.health_status_text(:healthy)).not_to eq(card)
    end

    # Everything else in this helper returns CSS classes or glyphs, not prose.
    it "leaves CSS class helpers untranslated" do
      expect(helper.health_status_color(:healthy)).to eq("success")
      expect(helper.error_rate_text_class(0.5)).to eq("text-success")
      expect(helper.trend_arrow(0)).to eq("→")
    end
  end

  describe RailsErrorDashboard::UserAgentHelper do
    # Mobile/Tablet/Bot/Desktop are ordinary words, so they translate.
    it "translates the device type" do
      iphone = helper.parse_user_agent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 " \
        "(KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
      )

      expect(iphone[:device_type]).to eq("Mobile")
    end

    it "reports a desktop browser as desktop" do
      desktop = helper.parse_user_agent(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      )

      expect(desktop[:device_type]).to eq("Desktop")
    end

    # Browser and OS names are brands and must survive translation as written.
    it "keeps the browser and OS brand names untranslated" do
      info = helper.parse_user_agent(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      )

      expect(info[:browser_name]).to eq("Chrome")
      expect(info[:os_name]).to eq("macOS")
    end

    it "translates the unknown fallbacks for a blank user agent" do
      info = helper.parse_user_agent("")

      expect(info[:browser_name]).to eq("Unknown")
      expect(info[:os_name]).to eq("Unknown")
      expect(info[:device_type]).to eq("Unknown")
    end

    # titleize applied English morphology to a machine identifier from the
    # browser gem. Nothing renders this value, so it stays raw.
    it "does not apply English morphology to the platform identifier" do
      info = helper.parse_user_agent(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      )

      expect(info[:platform]).to eq("mac")
    end

    # The icon helpers return markup, not prose.
    it "leaves the icon helpers untranslated" do
      info = { browser_name: "Chrome", os_name: "macOS", is_mobile: false, is_tablet: false }

      expect(helper.browser_icon(info)).to include("bi-browser-chrome")
      expect(helper.device_icon(info)).to include("bi-laptop")
    end
  end
end
