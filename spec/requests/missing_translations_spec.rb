# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Missing Translations page", type: :request do
  let!(:application) { create(:application) }
  let(:model) { RailsErrorDashboard::MissingTranslation }

  def create_row(locale: "en", key: "users.show.greeting", count: 1, source: nil, seen: 1.day.ago)
    model.create!(locale: locale, translation_key: key, miss_count: count, source: source,
                  first_seen_at: seen, last_seen_at: seen)
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.enable_missing_translation_tracking = false
  end

  describe "GET /error_dashboard/errors/missing_translations" do
    context "when tracking is disabled" do
      before { RailsErrorDashboard.configuration.enable_missing_translation_tracking = false }

      it "redirects to the errors index with an alert" do
        get "/error_dashboard/errors/missing_translations"

        expect(response).to redirect_to("/error_dashboard/errors")
        follow_redirect!
        expect(response.body).to include("Missing-translation tracking is not enabled")
        expect(response.body).to include("enable_missing_translation_tracking = true")
      end

      it "shows no nav entry" do
        get "/error_dashboard/errors"

        expect(response.body).not_to include("/error_dashboard/errors/missing_translations")
      end
    end

    context "when tracking is enabled" do
      before { RailsErrorDashboard.configuration.enable_missing_translation_tracking = true }

      it "renders the empty state with the how-it-works list" do
        get "/error_dashboard/errors/missing_translations"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No Missing Translations Recorded")
        expect(response.body).to include("enable_missing_translation_tracking = true")
        expect(response.body).to include("I18n.exception_handler")
      end

      it "links the page from the Diagnostics nav" do
        get "/error_dashboard/errors"

        expect(response.body).to include("/error_dashboard/errors/missing_translations")
      end

      it "lists recorded keys with locale, count and source, most-missed first" do
        create_row(key: "users.show.greeting", count: 12, source: "app/views/users/show.html.erb:4")
        create_row(key: "checkout.total", locale: "fr", count: 3)

        get "/error_dashboard/errors/missing_translations"

        body = response.body
        expect(body).to include("users.show.greeting", "checkout.total", "app/views/users/show.html.erb:4")
        expect(body.index("users.show.greeting")).to be < body.index("checkout.total")
        expect(body).to include(">12<", ">3<")
        expect(body).to include("Missing Keys", "Total Misses", "Locales Affected")
      end

      it "escapes a hostile key" do
        create_row(key: "<script>alert(1)</script>")

        get "/error_dashboard/errors/missing_translations"

        expect(response.body).not_to include("<script>alert(1)</script>")
        expect(response.body).to include("&lt;script&gt;")
      end

      it "shows the overflow notice when misses were dropped" do
        create_row(key: "k")
        create_row(locale: model::OVERFLOW_LOCALE, key: model::OVERFLOW_KEY, count: 42)

        get "/error_dashboard/errors/missing_translations"

        expect(response.body).to include("42 misses could not be attributed")
        expect(response.body).not_to include("__overflow__")
      end

      it "filters by the days parameter" do
        create_row(key: "old.key", seen: 40.days.ago)
        create_row(key: "new.key", seen: 2.days.ago)

        get "/error_dashboard/errors/missing_translations", params: { days: 7 }
        expect(response.body).to include("new.key")
        expect(response.body).not_to include("old.key")

        get "/error_dashboard/errors/missing_translations", params: { days: 90 }
        expect(response.body).to include("old.key", "new.key")
      end

      it "survives hostile parameters" do
        create_row(key: "k")

        get "/error_dashboard/errors/missing_translations", params: { days: { x: 1 }, page: "zzz", application_id: [ 1, 2 ] }

        expect(response).to have_http_status(:ok)
      end

      it "renders when the table has not been migrated yet" do
        allow(model).to receive(:table_exists?).and_return(false)

        get "/error_dashboard/errors/missing_translations"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No Missing Translations Recorded")
      end

      it "shows the setting on the settings page" do
        get "/error_dashboard/settings"

        expect(response.body).to include("enable_missing_translation_tracking")
      end
    end
  end
end
