# frozen_string_literal: true

require "rails_helper"

# Ukrainian is the second four-category plural locale (one/few/many/other),
# after Russian. It shares Russian's CLDR CATEGORY LIST and, for integers, its
# SELECTION RULE — but the rule is written out separately in PLURAL_RULES
# rather than aliased, so correcting one language can never silently move the
# other. These specs pin uk on its own for that reason.
#
# The lesson carried from the Japanese spike (P6-T4a) and repeated for Russian
# (P6-T4b): passing bin/i18n-check does NOT mean a locale renders. The checker
# validates the FILE; PrivateBackend decides which form is SELECTED. So these
# render real keys at real counts rather than inspecting the YAML.
RSpec.describe "Ukrainian locale", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.dashboard_locale = "uk"
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  it "ships uk as a selectable locale with its endonym" do
    expect(RailsErrorDashboard::I18nStore.available?("uk")).to be(true)
    expect(RailsErrorDashboard::I18nStore.locale_options).to include([ "uk", "Українська" ])
  end

  it "renders the dashboard in Ukrainian" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('lang="uk"')
    expect(response.body).to include("Помилки")
  end

  describe "plural form selection" do
    subject(:translate) do
      lambda { |count|
        RailsErrorDashboard::I18nStore.translate(
          "red.js.duration.hours", locale: "uk", count: count
        )
      }
    end

    it "uses `one` for 1 and for counts ending in 1 that are not 11" do
      expect(translate.call(1)).to eq("1 година")
      expect(translate.call(21)).to eq("21 година")
      expect(translate.call(101)).to eq("101 година")
    end

    it "uses `few` for counts ending in 2-4, excluding 12-14" do
      expect(translate.call(2)).to eq("2 години")
      expect(translate.call(4)).to eq("4 години")
      expect(translate.call(22)).to eq("22 години")
    end

    it "uses `many` for 0, 5-9, and the 11-14 exception band" do
      expect(translate.call(0)).to eq("0 годин")
      expect(translate.call(5)).to eq("5 годин")
      expect(translate.call(11)).to eq("11 годин")
      expect(translate.call(12)).to eq("12 годин")
      expect(translate.call(14)).to eq("14 годин")
      expect(translate.call(25)).to eq("25 годин")
    end

    # 11 and 111 both end in 1 but are `many`. The %100 guards are the only
    # thing separating them from the singular, so they are pinned alone.
    it "does not mistake 11 or 111 for the singular" do
      expect(translate.call(11)).not_to eq("11 година")
      expect(translate.call(111)).not_to eq("111 година")
      expect(translate.call(111)).to eq("111 годин")
    end
  end

  # en.yml spells `one: "1 hour"` with the numeral hardcoded, because English
  # `one` means exactly 1. Ukrainian `one` also covers 21 and 101, so uk.yml
  # MUST interpolate %{count} where English did not — otherwise 21 renders as
  # "1 година". bin/i18n-check allows this within a plural group.
  it "interpolates the count in `one`, which English hardcodes" do
    expect(
      RailsErrorDashboard::I18nStore.translate("red.js.duration.hours", locale: "en", count: 1)
    ).to eq("1 hour")

    expect(
      RailsErrorDashboard::I18nStore.translate("red.js.duration.hours", locale: "uk", count: 21)
    ).to eq("21 година")
  end

  it "renders plural forms through a real page, not just the store" do
    create_list(:error_log, 2, application: application)

    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/помилк/)
  end

  # Dates render as "9 березня 2026", which needs the GENITIVE case.
  # Nominative ("березень") is what a naive month list supplies and it reads
  # wrong in every date.
  it "supplies genitive month names for date rendering" do
    months = RailsErrorDashboard::I18nStore.subtree("red.js", locale: "uk")[:months]

    expect(months.first).to eq("січня")
    expect(months[2]).to eq("березня")
    expect(months).not_to include("березень")
  end

  it "leaves the host application's I18n untouched" do
    before_locale = I18n.locale
    before_available = I18n.available_locales.dup

    get "/error_dashboard/errors"

    expect(I18n.locale).to eq(before_locale)
    expect(I18n.available_locales).to eq(before_available)
  end
end
