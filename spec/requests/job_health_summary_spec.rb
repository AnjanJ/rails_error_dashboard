# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Job Health Summary page", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_system_health = false
  end

  describe "GET /error_dashboard/errors/job_health_summary" do
    context "when system_health is disabled" do
      before do
        RailsErrorDashboard.configuration.enable_system_health = false
      end

      it "redirects to errors index with alert" do
        get "/error_dashboard/errors/job_health_summary"
        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("System health is not enabled")
      end
    end

    context "when system_health is enabled" do
      before do
        RailsErrorDashboard.configuration.enable_system_health = true
      end

      it "returns 200" do
        get "/error_dashboard/errors/job_health_summary"
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state when no job data exists" do
        get "/error_dashboard/errors/job_health_summary"
        expect(response.body).to include("No Job Queue Data Found")
      end

      it "shows job stats from system_health" do
        create(:error_log,
          application: application,
          system_health: {
            "job_queue" => {
              "adapter" => "sidekiq",
              "enqueued" => 42,
              "failed" => 5,
              "dead" => 2,
              "retry" => 1,
              "workers" => 10
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/job_health_summary"
        expect(response.body).to include("sidekiq")
        expect(response.body).to include("42 enqueued")
      end

      it "displays summary cards" do
        create(:error_log,
          application: application,
          system_health: {
            "job_queue" => {
              "adapter" => "sidekiq",
              "enqueued" => 10,
              "failed" => 3
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/job_health_summary"
        expect(response.body).to include("Errors with Job Data")
        expect(response.body).to include("Total Failed Jobs")
        expect(response.body).to include("Adapters Detected")
      end

      it "accepts days parameter" do
        get "/error_dashboard/errors/job_health_summary", params: { days: 7 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 Days")
      end

      it "links to error detail pages" do
        error = create(:error_log,
          application: application,
          system_health: {
            "job_queue" => {
              "adapter" => "sidekiq",
              "enqueued" => 1,
              "failed" => 0
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/job_health_summary"
        expect(response.body).to include("/error_dashboard/errors/#{error.id}")
      end

      it "includes Active Job Guide link" do
        create(:error_log,
          application: application,
          system_health: {
            "job_queue" => {
              "adapter" => "sidekiq",
              "enqueued" => 1,
              "failed" => 0
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/job_health_summary"
        expect(response.body).to include("guides.rubyonrails.org/active_job_basics.html")
      end

      it "color-codes failed jobs with red badge" do
        create(:error_log,
          application: application,
          system_health: {
            "job_queue" => {
              "adapter" => "sidekiq",
              "enqueued" => 10,
              "failed" => 5
            }
          }.to_json,
          occurred_at: 1.day.ago)

        get "/error_dashboard/errors/job_health_summary"
        expect(response.body).to include("bg-danger")
      end
    end
  end
end
