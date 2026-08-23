# frozen_string_literal: true

require "rails_helper"

# Italian is a routine Romance locale in the same CLDR shape as fr/es/pt-BR:
# one/many/other, where `many` is reserved for large round numbers and the
# practical split for counts of errors is one/other.
#
# It ships no new machinery. What it did surface is a translation trap worth a
# spec: several English `one` forms interpolate a PRE-FORMATTED variable
# (%{value}, %{delta}, %{formatted}) rather than the raw count, so the number on
# screen need not be 1 — hardcoding "1 errore" there is wrong even though
# Italian `one` really does mean exactly 1. bin/i18n-check catches it; these
# examples pin the rendered result.
RSpec.describe "Italian locale", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.dashboard_locale = "it"
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  it "ships it as a selectable locale with its endonym" do
    expect(RailsErrorDashboard::I18nStore.available?("it")).to be(true)
    expect(RailsErrorDashboard::I18nStore.locale_options).to include([ "it", "Italiano" ])
  end

  it "renders the dashboard in Italian" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('lang="it"')
    expect(response.body).to include("Errori")
  end

  describe "plural form selection" do
    subject(:translate) do
      lambda { |count|
        RailsErrorDashboard::I18nStore.translate(
          "red.js.duration.hours", locale: "it", count: count
        )
      }
    end

    it "uses `one` for exactly 1 and `other` for everything else" do
      expect(translate.call(1)).to eq("1 ora")
      expect([ 0, 2, 5, 11, 21, 101 ].map { |n| translate.call(n) })
        .to eq([ "0 ore", "2 ore", "5 ore", "11 ore", "21 ore", "101 ore" ])
    end
  end

  # The trap this locale surfaced. en.yml writes "%{count} day" in `one`, not
  # "1 day", because the value shown is formatted upstream. A translation that
  # hardcodes the numeral silently prints the wrong number.
  it "interpolates in `one` wherever English does" do
    expect(
      RailsErrorDashboard::I18nStore.translate("red.settings.values.days", locale: "it", count: 1)
    ).to eq("1 giorno")

    expect(
      RailsErrorDashboard::I18nStore.translate(
        "red.notifications.baseline_alert.threshold_errors", locale: "it", count: 1, value: 1
      )
    ).to eq("1 errore")
  end

  it "renders plural forms through a real page, not just the store" do
    create_list(:error_log, 2, application: application)

    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/error/i)
  end

  # Unlike the Slavic locales, Italian months are NOMINATIVE and lowercase —
  # dates read "9 marzo 2026". No genitive form is involved.
  it "supplies lowercase nominative month names" do
    months = RailsErrorDashboard::I18nStore.subtree("red.js", locale: "it")[:months]

    expect(months.first).to eq("gennaio")
    expect(months[2]).to eq("marzo")
  end

  it "leaves the host application's I18n untouched" do
    before_locale = I18n.locale
    before_available = I18n.available_locales.dup

    get "/error_dashboard/errors"

    expect(I18n.locale).to eq(before_locale)
    expect(I18n.available_locales).to eq(before_available)
  end
end
