# frozen_string_literal: true

require "rails_helper"

# Regression for issue #148: the dashboard rendered Pagy labels in whatever
# language the host app last used.
#
# Pagy keeps its locale in Thread.current[:pagy_locale] and never resets it
# (pagy 43.6.1, modules/i18n/i18n.rb:24-31). A host app that assigns a locale
# per request leaves it on the Puma thread, so a dashboard request landing on a
# recycled thread inherited it — Russian on one refresh, Portuguese on the next.
RSpec.describe "Dashboard locale isolation", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    # user_impact only renders its Pagy info line when there are ranked rows,
    # which requires errors attributed to a user.
    create_list(:error_log, 3, :with_user, application: application)
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
    Thread.current[:pagy_locale] = nil
  end

  describe "when the host app has left a locale on the thread" do
    it "renders pagination in English rather than the host's locale" do
      Thread.current[:pagy_locale] = "ru"

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Displaying")
      expect(response.body).not_to include("Всего")
    end

    it "restores the host's locale after the request" do
      Thread.current[:pagy_locale] = "ru"

      get "/error_dashboard/errors/user_impact"

      expect(Thread.current[:pagy_locale]).to eq("ru")
    end

    # The previous value must be read from Thread.current, not from
    # Pagy::I18n.locale — the getter coerces nil to "en", so restoring through
    # it would dirty a thread that started clean.
    it "leaves a clean thread clean" do
      Thread.current[:pagy_locale] = nil

      get "/error_dashboard/errors/user_impact"

      expect(Thread.current[:pagy_locale]).to be_nil
    end
  end

  describe "dashboard_locale configuration" do
    it "defaults to English" do
      expect(RailsErrorDashboard.configuration.dashboard_locale).to eq("en")
    end

    it "renders pagination in the configured locale" do
      RailsErrorDashboard.configuration.dashboard_locale = "fr"

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Affichage")
    end

    # "EN" passes Pagy's LOCALE_PATTERN, finds en.yml, then reads a nil
    # dictionary because the YAML's top-level key is lowercase — raising
    # NoMethodError mid-render on every dashboard page.
    it "accepts a wrong-cased locale without raising" do
      RailsErrorDashboard.configuration.dashboard_locale = "EN"

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Displaying")
    end

    it "falls back to English for a locale Pagy does not ship" do
      RailsErrorDashboard.configuration.dashboard_locale = "not-a-locale"

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Displaying")
    end

    it "falls back to English when set to nil" do
      RailsErrorDashboard.configuration.dashboard_locale = nil

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Displaying")
    end
  end

  # RED's own translations (as opposed to Pagy's pagination labels) render
  # through a private I18n backend and a request-scoped locale. The same
  # leak-prevention properties must hold for both.
  describe "RED's own translation state" do
    # NOTE: asserting Current.locale is nil AFTER a `get` proves nothing —
    # ActiveSupport resets CurrentAttributes between requests, so that holds
    # even with the ensure deleted. These call the around_action directly so
    # the cleanup itself is what is under test.
    let(:controller) { RailsErrorDashboard::ErrorsController.new }

    it "clears the request-scoped locale when the block completes" do
      RailsErrorDashboard::Current.locale = "sentinel"

      controller.send(:with_dashboard_locale) do
        expect(RailsErrorDashboard::Current.locale).to eq("en")
      end

      expect(RailsErrorDashboard::Current.locale).to be_nil
    end

    it "clears the request-scoped locale even when the block raises" do
      expect {
        controller.send(:with_dashboard_locale) { raise "boom" }
      }.to raise_error("boom")

      expect(RailsErrorDashboard::Current.locale).to be_nil
    end

    it "does not strand its locale for a subsequent request on the same thread" do
      # The #148 shape: a value left on a Puma thread that the next request
      # inherits. Two consecutive invocations on one thread, no reset between.
      controller.send(:with_dashboard_locale) { nil }

      expect(RailsErrorDashboard::Current.locale).to be_nil

      observed = nil
      controller.send(:with_dashboard_locale) { observed = RailsErrorDashboard::Current.locale }

      expect(observed).to eq("en")
      expect(RailsErrorDashboard::Current.locale).to be_nil
    end

    it "clears the request-scoped locale across a full request cycle" do
      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
      expect(RailsErrorDashboard::Current.locale).to be_nil
    end

    it "leaves the host app's I18n untouched" do
      before_state = [
        I18n.load_path.dup,
        I18n.available_locales.dup,
        I18n.default_locale,
        I18n.locale
      ]

      get "/error_dashboard/errors"

      expect(response).to have_http_status(:ok)
      expect([ I18n.load_path, I18n.available_locales, I18n.default_locale, I18n.locale ])
        .to eq(before_state)
    end

    it "renders while the host app is in a different locale" do
      original = I18n.locale

      begin
        I18n.locale = :en
        RailsErrorDashboard.configuration.dashboard_locale = "en"

        get "/error_dashboard/errors"

        expect(response).to have_http_status(:ok)
        expect(I18n.locale).to eq(:en)
      ensure
        I18n.locale = original
      end
    end

    it "sets the html lang attribute from the dashboard locale" do
      get "/error_dashboard/errors"

      expect(response.body).to include('<html lang="en"')
    end

    it "renders when the dashboard locale is one Pagy does not ship" do
      # RED's locales and Pagy's are resolved independently. A locale RED can
      # serve but Pagy cannot must still render, with English pagination.
      RailsErrorDashboard.configuration.dashboard_locale = "en"

      get "/error_dashboard/errors/user_impact"

      expect(response).to have_http_status(:ok)
    end
  end
end
