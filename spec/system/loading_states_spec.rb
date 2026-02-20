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

  describe "async action button loading states" do
    let!(:unresolved_error) do
      create(:error_log,
        application: application,
        resolved: false,
        status: "new",
        priority_level: 0)
    end

    it "has loading action on modal submit buttons" do
      visit_error(unresolved_error)
      wait_for_page_load

      # The resolve button opens a modal
      expect(page).to have_css("[data-bs-target='#resolveModal']")

      # Modal submit buttons should have loading actions
      expect(page).to have_css("input[data-action='click->loading#click']", visible: :hidden)
    end
  end
end
