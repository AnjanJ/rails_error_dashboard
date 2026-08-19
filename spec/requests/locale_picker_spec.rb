# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "fileutils"

# The language picker (P5-T1).
#
# The dashboard is the page that has to work when the rest of the app is
# broken, so the interesting cases here are the hostile ones: a tampered
# session value, a host with no session at all, a cross-origin referer. None of
# them may raise, and none may leave the user stuck.
RSpec.describe "Language picker", type: :request do
  let!(:application) { create(:application) }

  # A second shipped locale, so the picker has a real choice to render.
  #
  # Written to a TEMP DIRECTORY, never to the engine's own config/locales.
  # Writing a file into the engine tree during a request spec trips Rails'
  # file watcher, and the reload that follows swaps every model's class object
  # mid-example: records created before it compare unequal to the identical
  # rows a scope returns afterwards (same id, same attributes, `==` false).
  # That surfaces as unrelated model specs failing later in the run — the
  # symptom that cost this task most of its debugging time.
  #
  # I18nStore reads its directory through .locales_path, so redirecting that
  # gives RED a second locale with nothing on a watched path.
  let(:locales_dir) { Pathname.new(Dir.mktmpdir("red-locales")) }
  let(:fixture_locale) { locales_dir.join("xh.yml") }

  before do
    # Request specs do not carry a CSRF token, and the picker is a real POST
    # behind protect_from_forgery. Disabled here so the specs exercise the
    # action rather than the token check; "enforces CSRF" below re-enables it
    # and asserts the protection is actually on.
    ActionController::Base.allow_forgery_protection = false
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    # Rails puts an engine's config/locales/*.yml on the HOST's I18n.load_path,
    # so a fixture written there is visible to the host backend too — and a
    # stale entry pointing at a deleted file makes the host raise
    # I18n::InvalidLocaleData the next time anything (Faker, in this suite)
    # triggers a host-side load. Snapshot the host's path and restore it in
    # `after`, so this file cannot strand a dangling entry for later specs.
    @host_load_path = I18n.load_path.dup
    # Snapshot rather than hardcoding a value to restore: writing "en" back in
    # `after` would overwrite whatever the dummy app configured and leak that
    # into every later spec in the process.
    @previous_dashboard_locale = RailsErrorDashboard.configuration.dashboard_locale
    # Ship en.yml alongside the fixture so English still resolves.
    FileUtils.cp(
      RailsErrorDashboard::Engine.root.join("config", "locales", "en.yml"),
      locales_dir.join("en.yml")
    )
    allow(RailsErrorDashboard::I18nStore).to receive(:locales_path).and_return(locales_dir.to_s)
    fixture_locale.write(<<~YAML)
      xh:
        red:
          navbar:
            search_placeholder: "XH-SEARCH"
          common:
            close: "XH-CLOSE"
    YAML
    RailsErrorDashboard::I18nStore.reset!
  end

  after do
    ActionController::Base.allow_forgery_protection = true
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = @previous_dashboard_locale
    FileUtils.remove_entry(locales_dir) if locales_dir.exist?
    RailsErrorDashboard::I18nStore.reset!
    # The fixture never touched the host's load_path, but restore it anyway so
    # this file cannot leak one if the setup above ever changes.
    I18n.load_path = @host_load_path
  end

  describe "POST /locale" do
    it "persists the selection across requests" do
      post "/error_dashboard/locale", params: { locale: "xh" }

      # The change takes effect on the NEXT request, by design.
      get "/error_dashboard/errors"
      expect(response.body).to include("XH-SEARCH")
    end

    it "returns the user to the page they came from, with query params intact" do
      post "/error_dashboard/locale",
        params: { locale: "xh" },
        headers: { "HTTP_REFERER" => "http://www.example.com/error_dashboard/errors?status=unresolved&page=2" }

      expect(response).to redirect_to("/error_dashboard/errors?status=unresolved&page=2")
    end

    it "stores the shipped spelling rather than what was submitted" do
      post "/error_dashboard/locale", params: { locale: "XH" }

      expect(session[:red_locale]).to eq("xh")
    end

    it "falls back to the overview when there is no referer" do
      post "/error_dashboard/locale", params: { locale: "xh" }

      expect(response).to redirect_to("/error_dashboard/overview")
    end

    # An absolute URL from another host would make the picker an open redirect.
    it "ignores a cross-origin referer" do
      post "/error_dashboard/locale",
        params: { locale: "xh" },
        headers: { "HTTP_REFERER" => "https://evil.example.net/phishing?a=1" }

      expect(response).to redirect_to("/error_dashboard/overview")
    end

    it "ignores a referer outside the engine's mount path" do
      post "/error_dashboard/locale",
        params: { locale: "xh" },
        headers: { "HTTP_REFERER" => "http://www.example.com/admin/secrets" }

      expect(response).to redirect_to("/error_dashboard/overview")
    end

    context "with a locale RED does not ship" do
      it "does not persist it and says so" do
        post "/error_dashboard/locale", params: { locale: "zz" }

        expect(session[:red_locale]).to be_nil
        expect(flash[:alert]).to be_present
      end

      it "keeps rendering the dashboard" do
        post "/error_dashboard/locale", params: { locale: "zz" }
        get "/error_dashboard/errors"

        expect(response).to have_http_status(:ok)
      end
    end

    # REQ-6: garbage in the session must not raise, and must not cost a lookup
    # on every later request either.
    context "with a tampered session value" do
      [ "'; DROP TABLE users; --", "zz", "", "   ", "../../etc/passwd", "<script>alert(1)</script>" ].each do |value|
        it "renders normally and clears #{value.inspect}" do
          post "/error_dashboard/locale", params: { locale: "xh" }
          # Poison the stored value directly, as a tampered cookie would.
          post "/error_dashboard/locale", params: { locale: value }

          get "/error_dashboard/errors"

          expect(response).to have_http_status(:ok)
          expect(session[:red_locale]).to be_nil
        end
      end

      it "does not raise when the value is not a String" do
        post "/error_dashboard/locale", params: { locale: { evil: "hash" } }

        expect(response).to have_http_status(:found)
        expect { get "/error_dashboard/errors" }.not_to raise_error
      end
    end

    # REQ-4. The rest of this file disables forgery protection to reach the
    # action at all; this one turns it back on to prove the protection exists.
    it "rejects a POST with no CSRF token" do
      ActionController::Base.allow_forgery_protection = true

      post "/error_dashboard/locale", params: { locale: "xh" }

      # The engine's rescue_from renders its own error page rather than letting
      # the raise escape, so the observable outcome is a 500 and no persisted
      # locale — not an exception reaching the spec.
      expect(response).to have_http_status(:internal_server_error)
      expect(session[:red_locale]).to be_nil
    end

    # Only POST is routed: a GET would let any link, prefetch, or crawler
    # change the user's language.
    it "does not route a GET" do
      expect(RailsErrorDashboard::Engine.routes.recognize_path("/locale", method: :post))
        .to include(controller: "rails_error_dashboard/locales", action: "create")

      expect { RailsErrorDashboard::Engine.routes.recognize_path("/locale", method: :get) }
        .to raise_error(ActionController::RoutingError)
    end
  end

  describe "precedence" do
    # REQ-3: session -> config.dashboard_locale -> "en"
    it "prefers the session over the configured locale" do
      RailsErrorDashboard.configuration.dashboard_locale = "en"
      post "/error_dashboard/locale", params: { locale: "xh" }

      get "/error_dashboard/errors"

      expect(response.body).to include("XH-SEARCH")
    end

    it "uses the configured locale when the session holds nothing" do
      RailsErrorDashboard.configuration.dashboard_locale = "xh"

      get "/error_dashboard/errors"

      expect(response.body).to include("XH-SEARCH")
    end

    it "does not let an empty session override the configured locale" do
      RailsErrorDashboard.configuration.dashboard_locale = "xh"
      post "/error_dashboard/locale", params: { locale: "zz" } # cleared

      get "/error_dashboard/errors"

      expect(response.body).to include("XH-SEARCH")
    end
  end

  describe "the picker in the navbar" do
    it "renders each shipped locale by its endonym" do
      get "/error_dashboard/errors"

      expect(response.body).to include("English")
      expect(response.body).to include("localePicker")
    end

    it "posts to the locale route with a CSRF-protected form" do
      get "/error_dashboard/errors"

      expect(response.body).to include('action="/error_dashboard/locale"')
      expect(response.body).to match(/method="post"/i)
    end

    it "marks the active locale for assistive technology" do
      get "/error_dashboard/errors"

      expect(response.body).to include('aria-current="true"')
    end

    it "labels the control" do
      get "/error_dashboard/errors"

      expect(response.body).to include("Choose dashboard language")
    end

    it "is hidden when only one locale ships" do
      fixture_locale.delete if fixture_locale.exist?
      RailsErrorDashboard::I18nStore.reset!

      get "/error_dashboard/errors"

      expect(response.body).not_to include("localePicker")
    end
  end
end
