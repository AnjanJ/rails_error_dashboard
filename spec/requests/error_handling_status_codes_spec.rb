# frozen_string_literal: true

require "rails_helper"

# The dashboard rescues StandardError so that it can never take the host app
# down. That catch-all must not flatten client mistakes into a 500, must not
# write unfiltered parameters to the log, and must not render the dashboard
# layout (queries, application names) to a caller who has not authenticated.
RSpec.describe "Dashboard error handling status codes", type: :request do
  let!(:application) { create(:application) }
  let(:error) { create(:error_log, application: application) }
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    original = {
      authenticate_with: config.authenticate_with,
      dashboard_username: config.dashboard_username,
      dashboard_password: config.dashboard_password
    }
    forgery = ActionController::Base.allow_forgery_protection

    begin
      example.run
    ensure
      original.each { |setting, value| config.public_send("#{setting}=", value) }
      ActionController::Base.allow_forgery_protection = forgery
    end
  end

  def logged_lines
    lines = []
    %i[error warn info debug].each do |level|
      allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &block|
        lines << (args.first || block&.call).to_s
        original.call(*args, &block)
      end
    end
    lines
  end

  def raise_in_index(exception)
    allow_any_instance_of(RailsErrorDashboard::ErrorsController).to receive(:index).and_raise(exception)
  end

  context "when authenticated" do
    before { config.authenticate_with = -> { true } }

    describe "a POST without a CSRF token" do
      before { ActionController::Base.allow_forgery_protection = true }

      it "answers 422 with its own copy, inside the dashboard layout" do
        post "/error_dashboard/errors/#{error.id}/resolve"

        expect(response).to have_http_status(422)
        expect(response.body).to include(I18n.t("red.errors_page.csrf.title"))
        expect(response.body).to include(I18n.t("red.errors_page.csrf.message"))
        expect(response.body).not_to include("Something went wrong")
        expect(response.body).to include("red-empty-state")
      end

      it "answers 401, not 422, when the caller is not authenticated either" do
        config.authenticate_with = nil

        post "/error_dashboard/errors/#{error.id}/resolve"

        expect(response).to have_http_status(:unauthorized)
      end

      it "does not resolve the error" do
        post "/error_dashboard/errors/#{error.id}/resolve"

        expect(error.reload.resolved).to be_falsey
      end

      it "logs one warning and no parameters" do
        lines = logged_lines

        post "/error_dashboard/errors/#{error.id}/resolve", params: { resolution_comment: "hunter2-in-a-comment" }

        mine = lines.grep(/\[RailsErrorDashboard\]/)
        expect(mine.size).to eq(1)
        expect(mine.first).to include("CSRF")
        expect(mine.join("\n")).not_to include("hunter2-in-a-comment")
      end
    end

    it "answers 400 for ActionController::ParameterMissing" do
      raise_in_index(ActionController::ParameterMissing.new(:error))

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include(I18n.t("red.errors_page.bad_request.title"))
      expect(response.body).not_to include("Something went wrong")
    end

    it "answers 400 for ActionController::BadRequest" do
      raise_in_index(ActionController::BadRequest.new("bad"))

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:bad_request)
    end

    it "answers 406 for ActionController::UnknownFormat" do
      raise_in_index(ActionController::UnknownFormat.new)

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:not_acceptable)
      expect(response.body).to include(I18n.t("red.errors_page.not_acceptable.title"))
    end

    # No dashboard page has a JSON (or XML, CSV...) template. Asking for one is
    # the client asking for something that does not exist, not a dashboard bug.
    %w[json xml csv].each do |format|
      it "answers 406, not 500, for ?format=#{format}" do
        get "/error_dashboard/errors", params: { format: format }
        expect(response).to have_http_status(:not_acceptable)

        get "/error_dashboard/overview", params: { format: format }
        expect(response).to have_http_status(:not_acceptable)
      end
    end

    it "still answers 500 when an HTML template is genuinely missing" do
      raise_in_index(ActionView::MissingTemplate.new([], "errors/nope", [], false, "template"))

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:internal_server_error)
    end

    it "still answers 500 with the generic page for an unexpected error" do
      raise_in_index(RuntimeError.new("boom"))

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("Something went wrong")
    end

    it "still answers 404 for a missing record" do
      get "/error_dashboard/errors/999999999"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("The requested error was not found")
    end

    it "logs filtered parameters, never the raw value of a filtered key" do
      raise_in_index(RuntimeError.new("boom"))
      lines = logged_lines

      # The host app's filter_parameters, as the request sees it.
      env_config = Rails.application.env_config
      was = env_config["action_dispatch.parameter_filter"]
      env_config["action_dispatch.parameter_filter"] = [ :password ]

      begin
        get "/error_dashboard/errors", params: { password: "hunter2", search: "visible-term" }
      ensure
        env_config["action_dispatch.parameter_filter"] = was
      end

      # Only the dashboard's own line: Rails' "Started GET ..." is the host's to filter.
      logged = lines.grep(/\AParams: /).join("\n")
      expect(logged).not_to include("hunter2")
      expect(logged).to include("[FILTERED]")
      expect(logged).to include("visible-term")
    end
  end

  # Nothing may be raised before authentication today, but the renderer must
  # not depend on that staying true.
  context "when an error is raised before authentication has succeeded" do
    before do
      config.authenticate_with = nil
      config.dashboard_username = "admin"
      config.dashboard_password = "secret123"
      allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_raise(RuntimeError, "boom before auth")
    end

    def count_queries
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    let(:headers) do
      { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret123") }
    end

    it "renders a bare response: no layout, no application names, no queries" do
      queries = count_queries { get "/error_dashboard/errors", headers: headers }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).not_to include("<html")
      expect(response.body).not_to include(application.name)
      expect(response.body).not_to include("boom before auth")
      expect(queries).to eq(0)
    end
  end
end
