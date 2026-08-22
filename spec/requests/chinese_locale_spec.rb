# frozen_string_literal: true

require "rails_helper"

# Simplified Chinese is the second `other`-only locale, after Japanese. It
# reuses everything the ja spike proved — single-category plurals, CJK date
# formats, inverted (shorter-than-English) expansion — and ships no new
# machinery.
#
# The reason it still gets its own specs is the runtime half. `zh-CN` was added
# to PrivateBackend::PLURAL_RULES back when ja shipped, and without that entry
# upstream's `count == 1 ? :one : :other` asks an other-only entry for `:one`,
# raises InvalidPluralizationData, and I18nStore rescues it into the ENGLISH
# fallback. Counts of 2 and above render fine, so the failure is invisible
# except at exactly count 1 — which is what the first example pins.
RSpec.describe "Chinese (Simplified) locale", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.dashboard_locale = "zh-CN"
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  it "ships zh-CN as a selectable locale with its endonym" do
    expect(RailsErrorDashboard::I18nStore.available?("zh-CN")).to be(true)
    expect(RailsErrorDashboard::I18nStore.locale_options).to include([ "zh-CN", "简体中文" ])
  end

  # pt-BR is the only other locale with a region subtag; zh-CN is the second,
  # so it exercises the case-insensitive resolve path too.
  it "resolves the region subtag case-insensitively" do
    expect(RailsErrorDashboard::I18nStore.resolve("zh-cn")).to eq("zh-CN")
    expect(RailsErrorDashboard::I18nStore.resolve("ZH-CN")).to eq("zh-CN")
  end

  it "renders the dashboard in Chinese" do
    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('lang="zh-CN"')
    expect(response.body).to include("错误")
  end

  describe "plural form selection" do
    subject(:translate) do
      lambda { |count|
        RailsErrorDashboard::I18nStore.translate(
          "red.js.duration.hours", locale: "zh-CN", count: count
        )
      }
    end

    # THE ONE THAT MATTERS. Without the zh-CN PLURAL_RULES entry this renders
    # the English "1 hour", because the raise is rescued into the fallback.
    it "renders Chinese at count 1, not the English fallback" do
      expect(translate.call(1)).to eq("1 小时")
      expect(translate.call(1)).not_to include("hour")
    end

    it "uses the single `other` form for every other count" do
      expect([ 0, 2, 5, 11, 21, 101 ].map { |n| translate.call(n) })
        .to eq([ "0 小时", "2 小时", "5 小时", "11 小时", "21 小时", "101 小时" ])
    end

    it "renders a real page string at count 1 as well" do
      expect(
        RailsErrorDashboard::I18nStore.translate(
          "red.errors.sidebar.occurred_times", locale: "zh-CN", count: 1
        )
      ).to eq("此错误已出现 1 次")
    end
  end

  it "renders plural forms through a real page, not just the store" do
    create_list(:error_log, 2, application: application)

    get "/error_dashboard/errors"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("错误")
  end

  # formatDateTime() is a chain of .replace() calls on %-directives and leaves
  # every other character alone, so the CJK literals between them survive.
  it "supplies numeric CJK month names and a year-month-day date order" do
    js = RailsErrorDashboard::I18nStore.subtree("red.js", locale: "zh-CN")

    expect(js[:months].first).to eq("1月")
    expect(js[:months][2]).to eq("3月")
    expect(js[:intl_locale]).to eq("zh-CN")

    expect(
      RailsErrorDashboard::I18nStore.translate("red.time.formats.date_only", locale: "zh-CN")
    ).to eq("%Y年%m月%d日")
  end

  it "leaves the host application's I18n untouched" do
    before_locale = I18n.locale
    before_available = I18n.available_locales.dup

    get "/error_dashboard/errors"

    expect(I18n.locale).to eq(before_locale)
    expect(I18n.available_locales).to eq(before_available)
  end
end
