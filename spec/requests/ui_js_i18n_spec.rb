# frozen_string_literal: true

require "rails_helper"

# P3-T3. The strings the server writes into inline <script> blocks: toasts,
# AI-help status text, section pills, and Chart.js axis and series labels.
#
# These are ERB, so they resolve at render time through red_js_t rather than
# being looked up in the browser. That is why they live under red.ui_js and not
# red.js — the payload ships on every page load and must carry only what the
# browser actually reads.
RSpec.describe "Server-rendered JS strings", type: :request do
  let!(:application) { create(:application) }
  let!(:error_log) { create(:error_log, application: application) }

  let(:original_platform_comparison) { RailsErrorDashboard.configuration.enable_platform_comparison }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    original_platform_comparison
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard::Current.locale = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  describe "toast and status strings" do
    it "renders the clipboard and loading strings from keys" do
      get "/error_dashboard/errors"

      expect(response.body).to include("Copied to clipboard!")
      expect(response.body).to include("Failed to copy to clipboard")
      expect(response.body).to include("Loading...")
    end

    it "renders the AI help status strings from keys" do
      get "/error_dashboard/errors"

      expect(response.body).to include("Enter a question first.")
      expect(response.body).to include("Streaming...")
      expect(response.body).to include("Request failed.")
    end
  end

  describe "section pills" do
    it "renders all thirteen labels on the error detail page" do
      get "/error_dashboard/errors/#{error_log.id}"

      %w[Error Request Deprecations Cache Breadcrumbs Similar Co-occurring
         Timeline Issue Discussion Cascades Patterns].each do |label|
        expect(response.body).to include("label: '#{label}'"),
          "expected a section pill labelled #{label.inspect}"
      end

      # Error-domain jargon, kept as-is like the rest of the glossary terms.
      expect(response.body).to include("label: 'N+1'")
    end
  end

  describe "chart labels" do
    it "renders analytics axis titles from keys" do
      get "/error_dashboard/errors/analytics"

      expect(response.body).to include("text: 'Date'")
      expect(response.body).to include("text: 'Number of Errors'")
    end

    # The chart block is guarded on @platform_health being non-empty, which
    # needs the feature enabled and errors carrying a platform.
    it "renders platform comparison series labels from keys" do
      RailsErrorDashboard.configuration.enable_platform_comparison = true
      create(:error_log, application: application, platform: "Web")
      create(:error_log, application: application, platform: "iOS")

      get "/error_dashboard/errors/platform_comparison"

      expect(response.body).to include("label: 'Total Errors'")
    ensure
      RailsErrorDashboard.configuration.enable_platform_comparison = original_platform_comparison
    end
  end

  # REQ-1 for the payload: red.ui_js is resolved server-side, so shipping it to
  # the browser would be bytes on every page load with nothing to read them.
  describe "payload scope" do
    it "does not ship the server-rendered ui_js namespace to the browser" do
      get "/error_dashboard/errors"

      payload = response.body[/window\.RED_I18N = (.*?);\s*$/m, 1]
      parsed = JSON.parse(payload.gsub('<\/', "</"))

      expect(parsed).not_to have_key("ui_js")
      expect(parsed["js"]).not_to have_key("sections")
      expect(parsed["js"]).not_to have_key("charts")
    end

    # The counterpart: the count is only known once a box is ticked, so the
    # browser must pick the plural form and this key has to ship.
    it "does ship the selected-count plural forms, which the browser resolves" do
      get "/error_dashboard/errors"

      payload = response.body[/window\.RED_I18N = (.*?);\s*$/m, 1]
      parsed = JSON.parse(payload.gsub('<\/', "</"))

      expect(parsed["js"]["selected"]).to eq("one" => "1 selected", "other" => "%{count} selected")
    end
  end
end
