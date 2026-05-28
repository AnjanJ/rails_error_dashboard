# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Errors show — Quick Actions", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.llm_provider = nil
    RailsErrorDashboard.configuration.llm_api_key = nil
    RailsErrorDashboard.configuration.llm_model = nil
    RailsErrorDashboard.configuration.llm_openai_endpoint = :auto
    ActionController::Base.allow_forgery_protection = true
  end

  describe "platform-filter quick action button" do
    # Regression: when error.platform is nil the button rendered with an empty
    # word ("View  Errors") and an essentially-broken filter link. Hide it
    # entirely instead — same pattern as the user_id button right above it.
    it "renders the button with the platform name when platform is set" do
      error = create(:error_log, application: application, platform: "iOS")
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).to include("View iOS Errors")
    end

    it "does not render the button when platform is nil" do
      error = create(:error_log, application: application, platform: nil)
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).not_to match(/View\s+Errors/)
    end

    it "does not render the button when platform is blank" do
      error = create(:error_log, application: application, platform: "")
      get "/error_dashboard/errors/#{error.id}"
      expect(response.body).not_to match(/View\s+Errors/)
    end
  end

  describe "AI Help" do
    it "does not render the AI Help button when LLM is not configured" do
      error = create(:error_log, application: application)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).not_to include('data-red-action="open-ai-help"')
      expect(response.body).not_to include('id="red-ai-help-panel"')
    end

    it "renders the AI Help button and panel when LLM is configured" do
      RailsErrorDashboard.configuration.llm_provider = :openai
      RailsErrorDashboard.configuration.llm_api_key = "test-key"
      RailsErrorDashboard.configuration.llm_model = "gpt-5"
      error = create(:error_log, application: application)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("AI Help")
      expect(response.body).to include("red-ai-help-panel")
      expect(response.body).to include("gpt-5")
    end

    it "returns a provider answer from the AI Help endpoint" do
      RailsErrorDashboard.configuration.llm_provider = :openai
      RailsErrorDashboard.configuration.llm_api_key = "test-key"
      RailsErrorDashboard.configuration.llm_model = "gpt-5"
      error = create(:error_log, application: application, error_type: "QuestDataCorruptionError")

      allow(RailsErrorDashboard::Services::LlmClient).to receive(:call).and_return(
        { answer: "Check the quest data at index 3.", provider: "openai", model: "gpt-5" }
      )

      post "/error_dashboard/errors/#{error.id}/ai_help",
        params: { question: "What caused this?" },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include(
        "answer" => "Check the quest data at index 3.",
        "provider" => "openai",
        "model" => "gpt-5"
      )
      expect(RailsErrorDashboard::Services::LlmClient).to have_received(:call).with(
        error: error,
        question: "What caused this?",
        context: a_string_including("QuestDataCorruptionError")
      )
    end

    it "rejects blank AI Help questions" do
      RailsErrorDashboard.configuration.llm_provider = :openai
      RailsErrorDashboard.configuration.llm_api_key = "test-key"
      error = create(:error_log, application: application)

      post "/error_dashboard/errors/#{error.id}/ai_help",
        params: { question: " " },
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Question cannot be blank")
    end
  end
end
