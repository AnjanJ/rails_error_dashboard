# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Quick Wins UI Features", type: :system do
  let!(:application) { create(:application) }

  describe "Exception Cause Chain" do
    let!(:error_with_cause) do
      create(:error_log,
        application: application,
        error_type: "ActionView::Template::Error",
        message: "undefined method 'name' for nil",
        exception_cause: [
          {
            "class_name" => "NoMethodError",
            "message" => "undefined method 'name' for nil:NilClass",
            "backtrace" => [ "app/models/user.rb:42:in `name'" ]
          },
          {
            "class_name" => "ActiveRecord::RecordNotFound",
            "message" => "Couldn't find User with id=999",
            "backtrace" => [ "app/controllers/users_controller.rb:10:in `show'" ]
          }
        ].to_json)
    end

    it "displays the cause chain section with each cause" do
      visit_error(error_with_cause)
      wait_for_page_load

      expect(page).to have_content("Exception Cause Chain")
      expect(page).to have_css(".badge.bg-secondary", text: "2")
      expect(page).to have_content("Caused by")
      expect(page).to have_content("NoMethodError")
      expect(page).to have_content("ActiveRecord::RecordNotFound")
      expect(page).to have_css(".card.border-warning", minimum: 2)
    end
  end

  describe "Enriched Request Context" do
    let!(:error_with_context) do
      create(:error_log,
        application: application,
        error_type: "ActionController::RoutingError",
        message: "No route matches [POST] /api/v2/widgets",
        http_method: "POST",
        hostname: "api.example.com",
        content_type: "application/json",
        request_duration_ms: 2345)
    end

    it "displays HTTP method, hostname, content type, and duration" do
      visit_error(error_with_context)
      wait_for_page_load

      # HTTP method badge
      expect(page).to have_css(".badge.bg-primary", text: "POST")

      # Hostname
      expect(page).to have_content("Hostname")
      expect(page).to have_content("api.example.com")

      # Content type
      expect(page).to have_content("Content Type")
      expect(page).to have_content("application/json")

      # Duration badge
      expect(page).to have_content("Request Duration")
      expect(page).to have_content("2.3s")
    end
  end

  describe "Structured Backtrace" do
    let!(:error_with_backtrace) do
      create(:error_log,
        application: application,
        error_type: "NoMethodError",
        message: "undefined method 'save!' for nil",
        backtrace: [
          "/home/deploy/myapp/app/models/user.rb:42:in `save_record'",
          "/home/deploy/myapp/app/controllers/users_controller.rb:15:in `create'",
          "/home/deploy/.gems/gems/actionpack-7.1.0/lib/action_controller/metal.rb:227:in `dispatch'",
          "/home/deploy/.gems/gems/railties-7.1.0/lib/rails/engine.rb:123:in `call'"
        ].join("\n"))
    end

    it "separates app code from framework code" do
      visit_error(error_with_backtrace)
      wait_for_page_load

      # "Your Code" section should be visible (expanded by default)
      expect(page).to have_content("Your Code")
      expect(page).to have_css(".badge.bg-success", text: /2 frames/)

      # "Framework & Gem Code" section should be present (collapsed by default)
      expect(page).to have_content("Framework & Gem Code")
      expect(page).to have_css(".badge.bg-secondary", text: /2 frames/)
    end
  end

  describe "Environment Info" do
    let!(:error_with_env) do
      create(:error_log,
        application: application,
        error_type: "RuntimeError",
        message: "something went wrong",
        environment_info: {
          rails_version: "7.1.3",
          ruby_version: "3.3.0",
          rails_env: "production",
          server: "puma",
          database_adapter: "postgresql"
        }.to_json)
    end

    it "displays environment details in the sidebar" do
      visit_error(error_with_env)
      wait_for_page_load

      expect(page).to have_content("Environment")
      expect(page).to have_content("7.1.3")
      expect(page).to have_content("3.3.0")
      expect(page).to have_css(".badge", text: "Production")
      expect(page).to have_content("Puma")
      expect(page).to have_content("postgresql")
    end
  end

  describe "Sensitive Data Filtering" do
    let!(:error_with_filtered_params) do
      create(:error_log,
        application: application,
        error_type: "ActiveRecord::RecordInvalid",
        message: "Validation failed: Email is invalid",
        request_params: {
          email: "user@example.com",
          password: "[FILTERED]",
          secret_key_base: "[FILTERED]",
          api_key: "[FILTERED]"
        }.to_json)
    end

    it "shows [FILTERED] placeholders and hides raw values" do
      visit_error(error_with_filtered_params)
      wait_for_page_load

      # Filtered values should appear as [FILTERED]
      expect(page).to have_content("[FILTERED]")

      # The email should be visible (not sensitive)
      expect(page).to have_content("user@example.com")
    end
  end

  describe "Auto-Reopen Badge" do
    let!(:reopened_error) do
      create(:error_log,
        application: application,
        error_type: "ActiveRecord::ConnectionTimeoutError",
        message: "could not obtain a connection from the pool within 5 seconds",
        reopened_at: 1.hour.ago,
        resolved: false,
        status: "new")
    end

    it "shows reopened badge on the detail page header" do
      visit_error(reopened_error)
      wait_for_page_load

      expect(page).to have_css(".badge.bg-warning", text: "Reopened")
    end

    it "shows reopened section in the sidebar" do
      visit_error(reopened_error)
      wait_for_page_load

      # Sidebar reopened section
      within(".col-md-4") do
        expect(page).to have_content("Reopened")
      end
    end

    it "shows reopened icon in the errors list" do
      visit_dashboard("/errors")
      wait_for_page_load

      expect(page).to have_css(".bi-arrow-counterclockwise")
    end
  end
end
