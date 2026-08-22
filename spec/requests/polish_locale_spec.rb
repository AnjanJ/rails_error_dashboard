# frozen_string_literal: true

require "rails_helper"

# Polish is the third four-category plural locale (one/few/many/other), after
# Russian and Ukrainian — AND IT IS NOT THE SAME RULE AS EITHER. Polish `one`
# is exactly 1, so 21 and 101 take `many` ("21 godzin"), where ru/uk take `one`
# ("21 час" / "21 година").
#
# That difference is invisible to bin/i18n-check: all three files carry the
# identical four categories, so the checker passes either way. Only selection
# shows it, which is why these specs render real keys at real counts.
RSpec.describe "Polish locale", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.dashboard_locale = "pl"
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  it "ships pl as a selectable locale with its endonym" do
    expect(RailsErrorDashboard::I18nStore.available?("pl")).to be(true)
    expect(RailsErrorDashboard::I18nStore.locale_options).to include([ "pl", "Polski" ])
  end

  it "renders the dashboard in Polish" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('lang="pl"')
    expect(response.body).to include("Błędy")
  end

  describe "plural form selection" do
    subject(:translate) do
      lambda { |count|
        RailsErrorDashboard::I18nStore.translate(
          "red.js.duration.hours", locale: "pl", count: count
        )
      }
    end

    # The defining difference from ru/uk, pinned first because it is the one
    # that a rule copied from another Slavic locale would get wrong.
    it "uses `one` for exactly 1 — NOT for 21 or 101" do
      expect(translate.call(1)).to eq("1 godzina")
      expect(translate.call(21)).to eq("21 godzin")
      expect(translate.call(101)).to eq("101 godzin")
    end

    it "uses `few` for counts ending in 2-4, excluding 12-14" do
      expect(translate.call(2)).to eq("2 godziny")
      expect(translate.call(4)).to eq("4 godziny")
      expect(translate.call(22)).to eq("22 godziny")
    end

    it "uses `many` for 0, 5-9, and the 11-14 exception band" do
      expect(translate.call(0)).to eq("0 godzin")
      expect(translate.call(5)).to eq("5 godzin")
      expect(translate.call(11)).to eq("11 godzin")
      expect(translate.call(12)).to eq("12 godzin")
      expect(translate.call(14)).to eq("14 godzin")
      expect(translate.call(111)).to eq("111 godzin")
    end

    # Stated against the shipped ru and uk files rather than in the abstract:
    # if someone later aliases pl's rule to either of them, this fails.
    it "disagrees with ru and uk at 21 and 101, as CLDR requires" do
      [ 21, 101 ].each do |n|
        pl = RailsErrorDashboard::I18nStore.translate("red.js.duration.hours", locale: "pl", count: n)
        uk = RailsErrorDashboard::I18nStore.translate("red.js.duration.hours", locale: "uk", count: n)
        ru = RailsErrorDashboard::I18nStore.translate("red.js.duration.hours", locale: "ru", count: n)

        expect(pl).to eq("#{n} godzin")
        expect(uk).to eq("#{n} година")
        expect(ru).to eq("#{n} час")
      end
    end
  end

  it "renders plural forms through a real page, not just the store" do
    create_list(:error_log, 2, application: application)

    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/błęd/i)
  end

  # Dates render as "9 marca 2026", which needs the GENITIVE case. Nominative
  # ("marzec") is what a naive month list supplies and it reads wrong.
  it "supplies genitive month names for date rendering" do
    months = RailsErrorDashboard::I18nStore.subtree("red.js", locale: "pl")[:months]

    expect(months.first).to eq("stycznia")
    expect(months[2]).to eq("marca")
    expect(months).not_to include("marzec")
  end

  it "leaves the host application's I18n untouched" do
    before_locale = I18n.locale
    before_available = I18n.available_locales.dup

    get "/error_dashboard/errors"

    expect(I18n.locale).to eq(before_locale)
    expect(I18n.available_locales).to eq(before_available)
  end
end
