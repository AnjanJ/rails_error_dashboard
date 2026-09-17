# frozen_string_literal: true

require "rails_helper"

# Every dashboard endpoint must refuse an unauthenticated request. This exists
# because LocalesController shipped without authentication: the filter was
# declared on ErrorsController rather than on ApplicationController, so a
# controller added later inherited no protection and nothing failed to say so.
#
# The generic example below walks the engine's real route set, so a controller
# added tomorrow is covered without anyone remembering to add it here.
RSpec.describe "Dashboard authentication", type: :request do
  let!(:application) { create(:application) }

  # These write to the global configuration singleton, so every one of them has
  # to be put back. Restoring only authenticate_with left "admin"/"secret123"
  # set for whatever ran next, and spec/requests/authentication_spec.rb logs in
  # as the default gandalf — it got a 401 and failed, but only on the seeds that
  # happened to order it after this file.
  around do |example|
    config = RailsErrorDashboard.configuration
    original = {
      authenticate_with: config.authenticate_with,
      dashboard_username: config.dashboard_username,
      dashboard_password: config.dashboard_password
    }

    config.authenticate_with = nil
    config.dashboard_username = "admin"
    config.dashboard_password = "secret123"

    begin
      example.run
    ensure
      original.each { |setting, value| config.public_send("#{setting}=", value) }
    end
  end

  def auth_header(user = "admin", pass = "secret123")
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
  end

  describe "without credentials" do
    it "refuses the locale picker (it is a state-changing POST)" do
      post "/error_dashboard/locale", params: { locale: "de" }

      expect(response).to have_http_status(:unauthorized)
      expect(session[:red_locale]).to be_nil
    end

    it "refuses the error list" do
      get "/error_dashboard/errors"
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses the overview" do
      get "/error_dashboard/overview"
      expect(response).to have_http_status(:unauthorized)
    end

    # The point of the whole spec: no GET route may answer 2xx unauthenticated.
    it "refuses every GET route the engine exposes" do
      leaked = RailsErrorDashboard::Engine.routes.routes.filter_map do |route|
        next unless route.verb.include?("GET")

        path = route.path.spec.to_s.sub("(.:format)", "")
        next if path.include?(":")  # needs an id; the controller-level filter covers these

        get "/error_dashboard#{path}"
        "#{path} -> #{response.status}" if response.status < 400
      rescue StandardError
        nil
      end

      expect(leaked).to be_empty, "unauthenticated GETs that did not refuse:\n  #{leaked.join("\n  ")}"
    end
  end

  describe "with valid credentials" do
    # CSRF is left ON for the unauthenticated examples above — authentication
    # must refuse before forgery protection is even reached, and disabling it
    # there would hide which of the two did the refusing. Here we are past
    # that question and testing the happy path, so the token check is disabled
    # the way the other picker specs do it: request specs cannot mint a valid
    # token, and the real picker uses button_to, which supplies one.
    before { ActionController::Base.allow_forgery_protection = false }
    after  { ActionController::Base.allow_forgery_protection = true }

    it "allows the locale picker through" do
      post "/error_dashboard/locale", params: { locale: "de" }, headers: auth_header

      expect(response).to have_http_status(:redirect)
      expect(session[:red_locale]).to eq("de")
    end

    it "allows the error list through" do
      get "/error_dashboard/errors", headers: auth_header
      expect(response).to have_http_status(:ok)
    end
  end

  describe "with wrong credentials" do
    it "refuses the locale picker" do
      post "/error_dashboard/locale", params: { locale: "de" }, headers: auth_header("admin", "wrong")

      expect(response).to have_http_status(:unauthorized)
      expect(session[:red_locale]).to be_nil
    end
  end

  # A Basic header does not have to decode to "user:pass". Without a colon the
  # password is nil, with nothing to decode both are. Those are failed logins
  # like any other: a 401 with a challenge, decided before any query runs.
  describe "with a malformed Basic header" do
    def count_queries
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    {
      "no colon (username only)" => "Basic #{Base64.strict_encode64('useronly')}",
      "the right username and no colon" => "Basic #{Base64.strict_encode64('admin')}",
      "an empty value" => "Basic ",
      "no value at all" => "Basic",
      "a value that is not base64" => "Basic !!!notbase64",
      "only a colon" => "Basic #{Base64.strict_encode64(':')}"
    }.each do |label, header|
      it "answers 401 with a challenge and runs no queries for #{label}" do
        queries = count_queries do
          get "/error_dashboard/errors", headers: { "HTTP_AUTHORIZATION" => header }
        end

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers["WWW-Authenticate"]).to include("Basic")
        expect(response.body).not_to include("bytesize")
        expect(response.body).not_to include("Something went wrong")
        expect(queries).to eq(0)
      end
    end

    it "still lets valid credentials through after the nil guard" do
      get "/error_dashboard/errors", headers: auth_header

      expect(response).to have_http_status(:ok)
    end

    # Fail closed: nil must never be coerced to "" and matched by an empty login.
    it "denies everyone when a credential is configured as nil, including an empty login" do
      RailsErrorDashboard.configuration.dashboard_username = nil
      RailsErrorDashboard.configuration.dashboard_password = nil

      [ auth_header("", ""), auth_header("admin", "secret123"),
        { "HTTP_AUTHORIZATION" => "Basic #{Base64.strict_encode64('admin')}" } ].each do |headers|
        get "/error_dashboard/errors", headers: headers

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "refuses a nil-password header even when the configured password is blank" do
      RailsErrorDashboard.configuration.dashboard_password = ""

      get "/error_dashboard/errors",
          headers: { "HTTP_AUTHORIZATION" => "Basic #{Base64.strict_encode64('admin')}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
