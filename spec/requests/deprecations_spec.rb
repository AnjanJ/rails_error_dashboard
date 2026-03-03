# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deprecations page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_breadcrumbs = false
  end

  describe "GET /error_dashboard/errors/deprecations" do
    context "when breadcrumbs are disabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/deprecations"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Breadcrumbs are not enabled")
      end
    end

    context "when breadcrumbs are enabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
      end

      it "returns 200" do
        get "/error_dashboard/errors/deprecations"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no deprecations exist" do
        get "/error_dashboard/errors/deprecations"
        expect(response.body).to include("No Deprecation Warnings Found")
      end

      it "shows deprecation warnings from breadcrumbs" do
        create(:error_log,
          application: application,
          breadcrumbs: [ { "c" => "deprecation", "m" => "Using old API", "meta" => { "caller" => "app/models/user.rb:5" } } ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/deprecations"
        expect(response.body).to include("Using old API")
        expect(response.body).to include("app/models/user.rb:5")
      end

      it "displays summary cards" do
        create(:error_log,
          application: application,
          breadcrumbs: [ { "c" => "deprecation", "m" => "Deprecated call" } ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/deprecations"
        expect(response.body).to include("Unique Warnings")
        expect(response.body).to include("Total Occurrences")
        expect(response.body).to include("Affected Errors")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/deprecations", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "links to error detail pages" do
        error = create(:error_log,
          application: application,
          breadcrumbs: [ { "c" => "deprecation", "m" => "Deprecated call" } ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/deprecations"
        expect(response.body).to include("/error_dashboard/errors/#{error.id}")
      end

      it "includes Rails Upgrade Guide link" do
        create(:error_log,
          application: application,
          breadcrumbs: [ { "c" => "deprecation", "m" => "Something deprecated" } ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/deprecations"
        expect(response.body).to include("guides.rubyonrails.org/upgrading_ruby_on_rails.html")
      end
    end
  end
end
