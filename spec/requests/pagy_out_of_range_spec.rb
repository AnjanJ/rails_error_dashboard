# frozen_string_literal: true

require "rails_helper"

# Regression: rescue_from Pagy::RangeError redirected to request.path which
# includes only the path component, dropping the entire query string. Users
# hitting an out-of-range page with active filters lost every filter on
# redirect.
RSpec.describe "Pagy out-of-range redirect", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
    create_list(:error_log, 3, application: application, error_type: "ArgumentError", resolved: false)
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "GET /error_dashboard/errors with out-of-range page param" do
    it "redirects to page 1 of the same filter set, preserving the filters" do
      get "/error_dashboard/errors", params: {
        error_type: "ArgumentError",
        unresolved: "0",
        page: 999_999
      }
      expect(response).to have_http_status(:see_other)
      expect(response.location).to include("error_type=ArgumentError")
      expect(response.location).to include("unresolved=0")
      expect(response.location).not_to include("page=999999")
      expect(response.location).not_to include("page=1") # not strictly required
    end

    # A 301 is cached by the browser: the out-of-range URL would keep bouncing
    # to page 1 even after enough errors arrive to make that page exist.
    it "does not answer with a cacheable permanent redirect" do
      get "/error_dashboard/errors", params: { page: 999_999 }
      expect(response.status).not_to eq(301)
      expect(response.status).not_to eq(308)
    end

    it "redirects to bare path when no other params were provided" do
      get "/error_dashboard/errors", params: { page: 999_999 }
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/error_dashboard/errors")
    end

    it "drops per_page from the redirect target when per_page is invalid" do
      # Regression: an earlier version of this rescue preserved every query
      # param except :page. With per_page=-1 (Pagy::OptionError) the redirect
      # carried per_page=-1 forward, which re-triggered the same OptionError
      # on the next request — infinite redirect loop. Drop both :page and
      # :per_page when redirecting.
      get "/error_dashboard/errors", params: { per_page: "-1" }
      expect(response).to have_http_status(:see_other)
      expect(response.location).not_to include("per_page=")
      # Following the redirect must reach 200, not loop.
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end
  end
  # per_page came straight from the query string into LIMIT, so one request
  # could ask the database for every row and render them all.
  describe "per_page upper bound" do
    # The limit may be inlined or sent as a bind, depending on the adapter.
    def limits_for
      seen = []
      collector = lambda do |_n, _s, _f, _i, payload|
        next unless payload[:sql].include?("LIMIT")

        binds = payload[:type_casted_binds]
        binds = binds.call if binds.respond_to?(:call)
        seen << "#{payload[:sql]} #{Array(binds).inspect}"
      end
      ActiveSupport::Notifications.subscribed(collector, "sql.active_record") { yield }
      seen.join("\n")
    end

    it "clamps a huge per_page to 100" do
      sql = limits_for { get "/error_dashboard/errors", params: { per_page: "9999999" } }

      expect(response).to have_http_status(:ok)
      expect(sql).not_to include("9999999")
      expect(sql).to match(/\b100\b/)
    end

    it "renders at most 100 rows however many are asked for" do
      create_list(:error_log, 105, application: application, resolved: false)

      get "/error_dashboard/errors", params: { per_page: "5000" }

      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/id="error_\d+"/).size).to eq(100)
    end

    it "leaves a value inside the range alone" do
      create_list(:error_log, 10, application: application, resolved: false)

      get "/error_dashboard/errors", params: { per_page: "5" }

      expect(response.body.scan(/id="error_\d+"/).size).to eq(5)
    end

    it "uses 25 when per_page is absent" do
      create_list(:error_log, 30, application: application, resolved: false)

      get "/error_dashboard/errors"

      expect(response.body.scan(/id="error_\d+"/).size).to eq(25)
    end

    it "clamps on the other paginated pages too" do
      get "/error_dashboard/errors/releases", params: { per_page: "9999999" }

      expect(response).to have_http_status(:ok)
    end

    it "does not raise for a per_page that arrives as a Hash or an Array" do
      get "/error_dashboard/errors", params: { per_page: { a: "1" } }
      expect(response.status).to be < 500

      get "/error_dashboard/errors", params: { per_page: [ "1", "2" ] }
      expect(response.status).to be < 500
    end

    it "reads per_page in exactly one place" do
      source = File.read(RailsErrorDashboard::Engine.root.join("app/controllers/rails_error_dashboard/errors_controller.rb"))

      expect(source).not_to include("params[:per_page]")
    end
  end
end
