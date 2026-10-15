# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Boot Errors page", type: :request do
  let!(:application) { create(:application) }

  def boot_row(**overrides)
    attrs = {
      application: application, platform: "boot_crash", error_type: "Zeitwerk::NameError",
      message: "expected file app/models/widget.rb to define constant Widget, but didn't",
      occurrence_count: 2, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago, occurred_at: 1.hour.ago,
      environment_info: { phase: "boot", boot: { file: "app/models/widget.rb", constant: "Widget" } }.to_json
    }.merge(overrides)
    create(:error_log, **attrs)
  end

  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }

  after { RailsErrorDashboard.reset_configuration! }

  context "when crash capture is disabled" do
    before { RailsErrorDashboard.configuration.enable_crash_capture = false }

    it "redirects with the alert and shows no nav entry" do
      get "/error_dashboard/errors/boot_errors"
      expect(response).to redirect_to("/error_dashboard/errors")
      follow_redirect!
      expect(response.body).to include("Boot error capture is not enabled", "enable_crash_capture = true")
      expect(response.body).not_to include("/error_dashboard/errors/boot_errors")
    end
  end

  context "when crash capture is enabled" do
    before { RailsErrorDashboard.configuration.enable_crash_capture = true }

    it "renders the empty state with how it works" do
      get "/error_dashboard/errors/boot_errors"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No Boot Errors Recorded", "Zeitwerk")
    end

    it "links the page from the Diagnostics nav" do
      get "/error_dashboard/errors"

      expect(response.body).to include("/error_dashboard/errors/boot_errors")
    end

    it "lists boot crashes with file, constant, count and a link to the error" do
      row = boot_row

      get "/error_dashboard/errors/boot_errors"

      body = response.body
      expect(body).to include("Zeitwerk::NameError", "app/models/widget.rb", "Widget", "/error_dashboard/errors/#{row.id}")
      expect(body).to include("Boot Errors", "Unresolved")
    end

    it "escapes a hostile message" do
      boot_row(message: "<script>alert(1)</script>")

      get "/error_dashboard/errors/boot_errors"

      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;")
    end

    it "survives hostile parameters" do
      boot_row

      get "/error_dashboard/errors/boot_errors", params: { days: { x: 1 }, page: "zzz", application_id: [ 1, 2 ] }

      expect(response).to have_http_status(:ok)
    end
  end
end
