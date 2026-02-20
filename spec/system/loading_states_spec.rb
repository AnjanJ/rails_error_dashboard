# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Loading States", type: :system do
  let!(:application) { create(:application) }
  let!(:error_log) { create(:error_log, application: application) }

  describe "skeleton screens" do
    it "has skeleton placeholders for dashboard stats" do
      visit_dashboard("/errors")
      wait_for_page_load

      # Skeleton containers exist but are hidden
      expect(page).to have_css(".loading-skeleton", visible: :hidden)
      expect(page).to have_css(".skeleton.skeleton-card", visible: :hidden)
    end

    it "has skeleton placeholders for error list" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_css(".skeleton.skeleton-row", visible: :hidden)
    end

    it "has a loading controller on the page" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_css("[data-controller='loading']")
    end
  end

  describe "button loading states" do
    it "has loading action on filter submit button" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_css("[data-loading-target='submitButton']")
    end
  end
end
