# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Database Setup & Multi-App Features", type: :system do
  describe "Single application" do
    let!(:application) { create(:application, name: "TestApp") }
    let!(:error_log) do
      create(:error_log,
        application: application,
        error_type: "NoMethodError",
        message: "undefined method 'foo' for nil:NilClass",
        resolved: false)
    end

    it "shows errors on the errors list page" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_content("NoMethodError")
      expect(page).to have_content("undefined method 'foo'")
    end

    it "does not show app switcher in navbar with only one app" do
      visit_dashboard("/errors")
      wait_for_page_load

      # With one app, there should be no "All Apps" dropdown
      expect(page).not_to have_css("a.dropdown-toggle", text: "All Apps")
    end

    it "shows error details correctly" do
      visit_error(error_log)
      wait_for_page_load

      expect(page).to have_content("NoMethodError")
      expect(page).to have_content("undefined method 'foo' for nil:NilClass")
    end
  end

  describe "Multi-application setup" do
    let!(:app1) { create(:application, name: "BlogApi") }
    let!(:app2) { create(:application, name: "AdminPanel") }

    let!(:blog_error) do
      create(:error_log,
        application: app1,
        error_type: "NoMethodError",
        message: "Blog API error",
        resolved: false)
    end

    let!(:admin_error) do
      create(:error_log,
        application: app2,
        error_type: "ActiveRecord::RecordNotFound",
        message: "Admin panel error",
        resolved: false)
    end

    it "shows app switcher dropdown in navbar with multiple apps" do
      visit_dashboard
      wait_for_page_load

      expect(page).to have_content("All Apps")
    end

    it "shows errors from all apps by default on overview" do
      visit_dashboard
      wait_for_page_load

      expect(page).to have_content("Blog API error")
      expect(page).to have_content("Admin panel error")
    end

    it "shows errors from all apps on the errors list page" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_content("Blog API error")
      expect(page).to have_content("Admin panel error")
    end

    it "filters errors by application on the errors list page" do
      visit_dashboard("/errors?application_id=#{app1.id}")
      wait_for_page_load

      expect(page).to have_content("Blog API error")
      expect(page).not_to have_content("Admin panel error")
    end

    it "shows error detail with correct application context" do
      visit_error(blog_error)
      wait_for_page_load

      expect(page).to have_content("NoMethodError")
      expect(page).to have_content("Blog API error")
    end
  end

  describe "Dashboard statistics with multiple apps" do
    let!(:app1) { create(:application, name: "ApiServer") }
    let!(:app2) { create(:application, name: "WebFrontend") }

    before do
      3.times do
        create(:error_log, application: app1, error_type: "RuntimeError",
          message: "api error", resolved: false)
      end
      2.times do
        create(:error_log, application: app2, error_type: "TypeError",
          message: "web error", resolved: false)
      end
    end

    it "shows combined unresolved count on overview" do
      visit_dashboard
      wait_for_page_load

      # Dashboard overview shows UNRESOLVED ERRORS count
      expect(page).to have_content("5")
      expect(page).to have_content("Pending resolution")
    end

    it "shows per-app stats when filtered" do
      visit_dashboard("/errors?application_id=#{app1.id}")
      wait_for_page_load

      # Should show only ApiServer errors
      expect(page).to have_content("api error")
      expect(page).not_to have_content("web error")
    end
  end
end
