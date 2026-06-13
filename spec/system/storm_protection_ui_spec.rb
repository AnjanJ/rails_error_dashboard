# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storm Protection UI", type: :system do
  let!(:application) { create(:application) }

  let!(:active_storm) do
    RailsErrorDashboard::StormEvent.create!(
      started_at: 10.minutes.ago, peak_rate_per_minute: 4200, reached_open: true,
      events_counted_only: 48_231, events_overflow: 120, fingerprints_affected: 37,
      top_fingerprints: [
        { "class" => "NoMethodError", "message" => "undefined method republish for nil", "count" => 40_000 }
      ].to_json
    )
  end

  before { RailsErrorDashboard.configuration.enable_storm_protection = true }
  after { RailsErrorDashboard.reset_configuration! }

  def switch_to_dark_theme
    page.execute_script("document.documentElement.setAttribute('data-theme', 'dark')")
  end

  def switch_to_light_theme
    page.execute_script("document.documentElement.setAttribute('data-theme', 'light')")
  end

  describe "storm banner" do
    it "shows the active storm banner in light theme" do
      visit_dashboard("/errors")
      wait_for_page_load
      switch_to_light_theme

      expect(page).to have_css("#storm-banner")
      expect(page).to have_content("Error storm in progress")
      expect(page).to have_link("View storm history")
      page.save_screenshot("tmp/screenshots/storm_banner_light.png")
    end

    it "remains legible in dark theme" do
      visit_dashboard("/errors")
      wait_for_page_load
      switch_to_dark_theme

      expect(page).to have_css("#storm-banner")
      expect(page).to have_content("Error storm in progress")
      page.save_screenshot("tmp/screenshots/storm_banner_dark.png")
    end
  end

  describe "storm history page" do
    it "renders episode details in light theme" do
      visit_dashboard("/errors/storms")
      wait_for_page_load
      switch_to_light_theme

      expect(page).to have_content("Storm History")
      expect(page).to have_content("Storm in progress")
      expect(page).to have_content("48,231")
      expect(page).to have_content("count-only")
      expect(page).to have_content("NoMethodError")
      page.save_screenshot("tmp/screenshots/storm_history_light.png")
    end

    it "renders in dark theme" do
      visit_dashboard("/errors/storms")
      wait_for_page_load
      switch_to_dark_theme

      expect(page).to have_content("Storm History")
      page.save_screenshot("tmp/screenshots/storm_history_dark.png")
    end

    it "appears in the Diagnostics nav section" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_link("Storms", href: %r{/errors/storms})
    end
  end
end
