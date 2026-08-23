# frozen_string_literal: true

require "rails_helper"

# P7-T1 REQ-5 / REQ-6: RED must render under a host whose I18n is configured
# hostilely, and must leave that configuration exactly as it found it.
RSpec.describe "P7-T1 host I18n isolation", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  # Snapshot every host I18n global REQ-1 names, run the block, and assert
  # nothing moved. Values, not just object identity.
  def expect_host_i18n_untouched
    before = {
      locale: I18n.locale,
      default_locale: I18n.default_locale,
      load_path: I18n.load_path.dup,
      available_locales: I18n.available_locales.dup,
      backend: I18n.backend,
      exception_handler: I18n.exception_handler,
      enforce: I18n.enforce_available_locales
    }
    yield
    aggregate_failures "host I18n after RED rendered" do
      expect(I18n.locale).to eq(before[:locale])
      expect(I18n.default_locale).to eq(before[:default_locale])
      expect(I18n.load_path).to eq(before[:load_path])
      expect(I18n.available_locales).to eq(before[:available_locales])
      expect(I18n.backend).to equal(before[:backend])
      expect(I18n.exception_handler).to equal(before[:exception_handler])
      expect(I18n.enforce_available_locales).to eq(before[:enforce])
    end
  end

  describe "REQ-5 — host in a non-English locale" do
    # RED's locale must be independent of the host's in BOTH directions:
    # the host's locale must not leak into RED, and RED must not touch it.
    [ "fr", "ja" ].each do |host_locale|
      it "renders RED in its own locale while the host is #{host_locale}" do
        original = I18n.locale
        I18n.available_locales |= [ host_locale.to_sym ]
        I18n.locale = host_locale.to_sym
        RailsErrorDashboard.configuration.dashboard_locale = "de"

        expect_host_i18n_untouched do
          get "/error_dashboard/errors"
        end

        expect(response).to have_http_status(:ok)
        # RED rendered ITS configured locale, not the host's.
        expect(response.body).to include('lang="de"')
        expect(response.body).to include("Fehler")
      ensure
        I18n.locale = original
      end
    end
  end

  describe "REQ-6 — hostile host configuration" do
    it "renders when the host enforces a narrow available_locales allowlist" do
      # This is DEFECT 1: the latch is one-way, so once anything assigns to
      # available_locales, a locale off the list is dropped from store_translations.
      original_enforce = I18n.enforce_available_locales
      original_available = I18n.available_locales.dup
      I18n.enforce_available_locales = true
      I18n.available_locales = [ :en ]   # arms the latch; excludes de
      RailsErrorDashboard::I18nStore.reset!
      RailsErrorDashboard.configuration.dashboard_locale = "de"

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fehler"), "German was stripped by the host's allowlist"
    ensure
      I18n.enforce_available_locales = original_enforce
      I18n.available_locales = original_available
      RailsErrorDashboard::I18nStore.reset!
    end

    it "renders when the host raises on missing translations" do
      original = I18n.exception_handler
      I18n.exception_handler = ->(exception, _locale, _key, _options) { raise exception.to_exception }
      RailsErrorDashboard.configuration.dashboard_locale = "de"

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
    ensure
      I18n.exception_handler = original
    end

    it "renders when the host's backend is replaced entirely" do
      original = I18n.backend
      I18n.backend = I18n::Backend::Simple.new
      RailsErrorDashboard.configuration.dashboard_locale = "ru"

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ошибки")
    ensure
      I18n.backend = original
    end

    it "does not absorb the host's load_path into RED's dictionary" do
      # DEFECT 2. If the host's load_path leaked in, a host key would resolve
      # through RED's store.
      expect(RailsErrorDashboard::I18nStore.translate("faker.name.first_name", locale: "en"))
        .to eq("First name") # humanized-key fallback, i.e. NOT found
    end
  end

  describe "REQ-1 — RED never mutates host I18n across a locale switch" do
    it "leaves every host global untouched through the picker flow" do
      expect_host_i18n_untouched do
        post "/error_dashboard/locale", params: { locale: "ja" }
        get "/error_dashboard/errors"
      end
      expect(response).to have_http_status(:ok)
    end
  end
end
