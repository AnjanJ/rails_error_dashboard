# frozen_string_literal: true

require "rails_helper"

RSpec.describe "N+1 Query Summary page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_breadcrumbs = false
  end

  describe "GET /error_dashboard/errors/n_plus_one_summary" do
    context "when breadcrumbs are disabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/n_plus_one_summary"
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
        get "/error_dashboard/errors/n_plus_one_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no N+1 patterns exist" do
        get "/error_dashboard/errors/n_plus_one_summary"
        expect(response.body).to include("No N+1 Query Patterns Found")
      end

      it "shows N+1 patterns from breadcrumbs" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "sql", "m" => 'SELECT "users".* FROM "users" WHERE "users"."id" = 1', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "users".* FROM "users" WHERE "users"."id" = 2', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "users".* FROM "users" WHERE "users"."id" = 3', "d" => 1.0 }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/n_plus_one_summary"
        expect(response.body).to include("users")
      end

      it "displays summary cards" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "sql", "m" => 'SELECT "users".* FROM "users" WHERE "users"."id" = 1', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "users".* FROM "users" WHERE "users"."id" = 2', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "users".* FROM "users" WHERE "users"."id" = 3', "d" => 1.0 }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/n_plus_one_summary"
        expect(response.body).to include("Unique Patterns")
        expect(response.body).to include("Total Occurrences")
        expect(response.body).to include("Affected Errors")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/n_plus_one_summary", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "links to error detail pages" do
        error = create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "sql", "m" => 'SELECT "posts".* FROM "posts" WHERE "posts"."id" = 1', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "posts".* FROM "posts" WHERE "posts"."id" = 2', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "posts".* FROM "posts" WHERE "posts"."id" = 3', "d" => 1.0 }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/n_plus_one_summary"
        expect(response.body).to include("/error_dashboard/errors/#{error.id}")
      end

      it "includes Rails Eager Loading Guide link" do
        create(:error_log,
          application: application,
          breadcrumbs: [
            { "c" => "sql", "m" => 'SELECT "x".* FROM "x" WHERE "x"."id" = 1', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "x".* FROM "x" WHERE "x"."id" = 2', "d" => 1.0 },
            { "c" => "sql", "m" => 'SELECT "x".* FROM "x" WHERE "x"."id" = 3', "d" => 1.0 }
          ].to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/n_plus_one_summary"
        expect(response.body).to include("guides.rubyonrails.org/active_record_querying.html#eager-loading-associations")
      end
    end
  end
end
