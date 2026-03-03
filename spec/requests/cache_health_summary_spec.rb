# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cache Health Summary page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_breadcrumbs = false
  end

  describe "GET /error_dashboard/errors/cache_health_summary" do
    context "when breadcrumbs are disabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/cache_health_summary"
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
        get "/error_dashboard/errors/cache_health_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no cache activity exists" do
        get "/error_dashboard/errors/cache_health_summary"
        expect(response.body).to include("No Cache Activity Found")
      end

      it "shows cache stats from breadcrumbs" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "cache", "m" => "cache read: users/1", "d" => 0.5, "meta" => { "hit" => true } },
            { "c" => "cache", "m" => "cache read: users/2", "d" => 1.0, "meta" => { "hit" => false } },
            { "c" => "cache", "m" => "cache write: users/3", "d" => 0.3 }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/cache_health_summary"
        expect(response.body).to include("50.0%")
      end

      it "displays summary cards" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "cache", "m" => "cache read: x", "d" => 0.5, "meta" => { "hit" => true } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/cache_health_summary"
        expect(response.body).to include("Errors with Cache")
        expect(response.body).to include("Avg Hit Rate")
        expect(response.body).to include("Total Cache Ops")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/cache_health_summary", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "links to error detail pages" do
        error = create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "cache", "m" => "cache read: y", "d" => 0.5, "meta" => { "hit" => true } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/cache_health_summary"
        expect(response.body).to include("/error_dashboard/errors/#{error.id}")
      end

      it "includes Rails Caching Guide link" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "cache", "m" => "cache read: z", "d" => 0.5, "meta" => { "hit" => true } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/cache_health_summary"
        expect(response.body).to include("guides.rubyonrails.org/caching_with_rails.html")
      end

      it "color-codes hit rates" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "cache", "m" => "cache read: a", "d" => 0.5, "meta" => { "hit" => false } },
            { "c" => "cache", "m" => "cache read: b", "d" => 0.5, "meta" => { "hit" => false } }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/cache_health_summary"
        expect(response.body).to include("bg-danger")
        expect(response.body).to include("0.0%")
      end
    end
  end
end
