# frozen_string_literal: true

require "rails_helper"

# The layout renders on every dashboard page, so a translation mistake here is
# a mistake everywhere. These specs pin the two properties that extraction can
# quietly break: the strings still render, and the desktop sidebar and mobile
# offcanvas stay in agreement.
RSpec.describe "Layout translations", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "navigation" do
    it "renders the section headings" do
      get "/error_dashboard/errors"

      expect(response.body).to include("Core")
      expect(response.body).to include("Insights")
    end

    it "renders core nav labels" do
      get "/error_dashboard/errors"

      expect(response.body).to include("Overview")
      expect(response.body).to include("Analytics")
      expect(response.body).to include("Settings")
    end

    # The mobile offcanvas duplicates the sidebar's destinations. Both read the
    # same keys; if one is edited to a literal, this catches the drift.
    it "labels the same destination identically in the sidebar and the mobile menu" do
      get "/error_dashboard/errors"

      %w[Overview Analytics Correlation Releases Settings].each do |label|
        expect(response.body.scan(/>\s*#{Regexp.escape(label)}\s*</).size).to be >= 2,
          "expected #{label.inspect} in both the sidebar and the mobile offcanvas"
      end
    end
  end

  describe "navbar" do
    it "renders the search placeholder and control titles" do
      get "/error_dashboard/errors"

      expect(response.body).to include('placeholder="Search errors... /"')
      expect(response.body).to include('title="Toggle theme"')
      expect(response.body).to include('title="Toggle sidebar (S)"')
    end
  end

  describe "keyboard shortcuts modal" do
    it "renders translated labels but leaves the key names literal" do
      get "/error_dashboard/errors"

      expect(response.body).to include("Keyboard Shortcuts")
      expect(response.body).to include("Refresh page")
      # Physical keys are not words and must not be translated.
      expect(response.body).to include("<kbd>R</kbd>")
      expect(response.body).to include("<kbd>?</kbd>")
    end
  end

  describe "footer" do
    it "keeps the author link markup intact through interpolation" do
      get "/error_dashboard/errors"

      expect(response.body).to include('Built with ❤️ by <a href="https://anjan.dev" target="_blank">Anjan Jagirdar</a>')
    end
  end

  describe "credentials banner" do
    it "renders the warning with its code markup unescaped" do
      allow(RailsErrorDashboard.configuration).to receive(:default_credentials?).and_return(true)

      get "/error_dashboard/errors"

      expect(response.body).to include("Security Warning:")
      # body_html carries <code> tags — escaping them would show raw markup.
      expect(response.body).to include("<code>ERROR_DASHBOARD_USER</code>")
      expect(response.body).not_to include("&lt;code&gt;ERROR_DASHBOARD_USER")
    end
  end

  describe "html lang" do
    it "reflects the dashboard locale" do
      get "/error_dashboard/errors"

      expect(response.body).to include('<html lang="en"')
    end
  end
end
