# frozen_string_literal: true

require "rails_helper"

# Russian is the first FOUR-category plural locale RED ships (one/few/many/
# other). Every locale before it used at most three, so these specs cover
# machinery that nothing else exercises.
#
# The lesson carried over from the Japanese spike (P6-T4a): passing
# bin/i18n-check does NOT mean a locale renders. The checker validates the
# FILE; PrivateBackend decides which form is SELECTED. Both had an
# English-shaped assumption, and only rendering a real key at a real count
# catches the second one. So these render rather than inspect the YAML.
RSpec.describe "Russian locale", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.dashboard_locale = "ru"
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  it "ships ru as a selectable locale with its endonym" do
    expect(RailsErrorDashboard::I18nStore.available?("ru")).to be(true)
    expect(RailsErrorDashboard::I18nStore.locale_options).to include([ "ru", "Русский" ])
  end

  it "renders the dashboard in Russian" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('lang="ru"')
    expect(response.body).to include("Ошибки")
  end

  # The heart of it. Russian selects `one` for 1, 21, 101 — NOT only for 1 —
  # and `many` for 11 and 111 despite those ending in 1. A rule written on
  # %10 alone renders "11 ошибка" instead of "11 ошибок".
  describe "plural form selection" do
    subject(:translate) do
      lambda { |count|
        RailsErrorDashboard::I18nStore.translate(
          "red.js.duration.hours", locale: "ru", count: count
        )
      }
    end

    it "uses `one` for 1 and for counts ending in 1 that are not 11" do
      expect(translate.call(1)).to eq("1 час")
      expect(translate.call(21)).to eq("21 час")
      expect(translate.call(101)).to eq("101 час")
    end

    it "uses `few` for counts ending in 2-4, excluding 12-14" do
      expect(translate.call(2)).to eq("2 часа")
      expect(translate.call(4)).to eq("4 часа")
      expect(translate.call(22)).to eq("22 часа")
    end

    it "uses `many` for 0, 5-9, and the 11-14 exception band" do
      expect(translate.call(5)).to eq("5 часов")
      expect(translate.call(11)).to eq("11 часов")
      expect(translate.call(12)).to eq("12 часов")
      expect(translate.call(14)).to eq("14 часов")
      expect(translate.call(25)).to eq("25 часов")
    end

    # 11 and 111 both end in 1 but are `many`. This is the single mistake most
    # likely to be made when adding a Slavic locale, so it is pinned alone.
    it "does not mistake 11 or 111 for the singular" do
      expect(translate.call(11)).not_to eq("11 час")
      expect(translate.call(111)).not_to eq("111 час")
      expect(translate.call(111)).to eq("111 часов")
    end
  end

  # en.yml spells `one: "1 second"` with the numeral hardcoded, because
  # English `one` means exactly 1. Russian `one` also covers 21 and 101, so
  # ru.yml MUST interpolate %{count} where English did not — otherwise 21
  # renders as "1 час". bin/i18n-check allows this within a plural group.
  it "interpolates the count in `one`, which English hardcodes" do
    source = RailsErrorDashboard::I18nStore.translate(
      "red.js.duration.hours", locale: "en", count: 1
    )
    expect(source).to eq("1 hour")

    expect(
      RailsErrorDashboard::I18nStore.translate(
        "red.js.duration.hours", locale: "ru", count: 21
      )
    ).to eq("21 час")
  end

  it "renders plural forms through a real page, not just the store" do
    create_list(:error_log, 2, application: application)

    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    # The summary line pluralises on the visible error count.
    expect(response.body).to match(/ошиб/)
  end

  # Dates render as "9 марта 2026", which needs the GENITIVE case. Nominative
  # ("март") is what a naive month list supplies and it reads wrong in a date.
  it "supplies genitive month names for date rendering" do
    # subtree returns symbol keys, matching the JS payload builder.
    months = RailsErrorDashboard::I18nStore.subtree("red.js", locale: "ru")[:months]

    expect(months.first).to eq("января")
    expect(months[2]).to eq("марта")
    expect(months).not_to include("март")
  end

  it "leaves the host application's I18n untouched" do
    before_locale = I18n.locale
    before_available = I18n.available_locales.dup

    get "/error_dashboard/errors"

    expect(I18n.locale).to eq(before_locale)
    expect(I18n.available_locales).to eq(before_available)
  end
end
