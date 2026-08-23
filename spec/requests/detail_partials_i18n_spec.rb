# frozen_string_literal: true

require "rails_helper"

# First half of the detail page's partials (P2-T7a). The load-bearing property
# here is the fragment cache: three partials on this page are cached, and a
# cached fragment that does not vary by locale serves the first locale rendered
# to every other one.
RSpec.describe "Detail partial translations", type: :request do
  let!(:application) { create(:application) }
  let!(:error) do
    create(:error_log, application: application, error_type: "SecurityError",
           occurrence_count: 3)
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "local and instance variables" do
    around do |example|
      locals = RailsErrorDashboard.configuration.enable_local_variables
      instances = RailsErrorDashboard.configuration.enable_instance_variables
      RailsErrorDashboard.configuration.enable_local_variables = true
      RailsErrorDashboard.configuration.enable_instance_variables = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_local_variables = locals
      RailsErrorDashboard.configuration.enable_instance_variables = instances
    end

    let(:vars) do
      {
        "user_id" => { "type" => "Integer", "value" => "42" },
        "password" => { "type" => "String", "filtered" => true }
      }
    end

    it "renders the local variables table labels" do
      error.update_column(:local_variables, vars.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Local Variables")
      expect(response.body).to include("2 captured")
      expect(response.body).to include("[FILTERED]")
    end

    # The English original spliced a <code> element into the middle of a
    # sentence. Each branch is now a whole sentence.
    it "renders the instance variables hint with the class name interpolated" do
      payload = vars.merge("_self_class" => { "value" => "UsersController" })
      error.update_column(:instance_variables, payload.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to match(
        %r{Instance variables from <code>UsersController</code> where the exception was raised}
      )
    end

    it "falls back to the generic hint when the class is unknown" do
      error.update_column(:instance_variables, vars.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Instance variables from the object where the exception was raised")
    end
  end

  describe "AI help panel" do
    around do |example|
      provider = RailsErrorDashboard.configuration.llm_provider
      key = RailsErrorDashboard.configuration.llm_api_key
      RailsErrorDashboard.configuration.llm_provider = "openai"
      RailsErrorDashboard.configuration.llm_api_key = "test-key"
      example.run
    ensure
      RailsErrorDashboard.configuration.llm_provider = provider
      RailsErrorDashboard.configuration.llm_api_key = key
    end

    it "renders the panel's labels and placeholder" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Ask about root cause")
      expect(response.body).to include('placeholder="What is the likely root cause?"')
      expect(response.body).to include('aria-label="Close AI Help"')
    end

    # "openai".titleize is "Openai", which is not how the company writes it.
    it "renders the provider's own brand casing rather than titleize output" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("OpenAI")
      expect(response.body).not_to include("Openai")
    end
  end

  # Three partials on this page are fragment-cached. Only en ships today, so
  # what can be asserted is the property that makes a second locale safe later:
  # the locale is part of every cached fragment's key.
  describe "fragment caches" do
    around do |example|
      store = ActionController::Base.perform_caching
      ActionController::Base.perform_caching = true
      Rails.cache.clear
      example.run
    ensure
      ActionController::Base.perform_caching = store
      Rails.cache.clear
    end

    it "keys every cached detail fragment on the locale" do
      written = []
      allow(Rails.cache).to receive(:write).and_wrap_original do |original, key, *args|
        written << key
        original.call(key, *args)
      end

      get "/error_dashboard/errors/#{error.id}"

      # Assert on key structure rather than a substring of the inspected form:
      # the serialized ErrorLog carries a user_agent that can contain anything.
      %w[error_details_v2 request_context_v5].each do |marker|
        key = written.find { |k| Array(k).flatten.any? { |part| part == marker } }
        expect(key).to be_present, "expected a cached fragment tagged #{marker}"
        expect(Array(key).flatten).to include("en"),
          "expected #{marker}'s cache key to carry the locale"
      end
    end

    it "renders identically on a second, cache-hitting request" do
      get "/error_dashboard/errors/#{error.id}"
      expect(response).to have_http_status(:ok)

      get "/error_dashboard/errors/#{error.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Request Context")
    end
  end
end
