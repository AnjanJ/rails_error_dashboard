# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::I18nHelper, type: :helper do
  after do
    RailsErrorDashboard::Current.locale = nil
    RailsErrorDashboard.configuration.dashboard_locale = "en"
  end

  describe "#red_t" do
    it "translates a key" do
      expect(helper.red_t("red.common.not_available")).to eq("N/A")
    end

    it "interpolates arguments" do
      expect(helper.red_t("red.time.ago", duration: "3 hours")).to eq("3 hours ago")
    end

    it "returns readable text for a missing key rather than raising" do
      expect(helper.red_t("red.nope.absent_key")).to eq("Absent key")
    end

    it "escapes HTML in translated values" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { xss_probe: "<script>alert(1)</script>" }
      )

      result = helper.red_t("red.xss_probe")

      expect(result).not_to include("<script>")
      expect(result).to include("&lt;script&gt;")
    end

    it "escapes HTML in interpolated values" do
      result = helper.red_t("red.time.ago", duration: "<script>alert(1)</script>")

      expect(result).not_to include("<script>")
    end

    it "marks _html-suffixed keys as safe" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { safe_probe_html: "<strong>bold</strong>" }
      )

      expect(helper.red_t("red.safe_probe_html")).to be_html_safe
    end

    [ nil, "", 123, [] ].each do |bad_key|
      it "does not raise for key #{bad_key.inspect}" do
        expect { helper.red_t(bad_key) }.not_to raise_error
      end
    end
  end

  describe "#red_tp" do
    before do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { count_probe: { one: "1 error", other: "%{count} errors" } }
      )
    end

    it "selects the singular form" do
      expect(helper.red_tp("red.count_probe", count: 1)).to eq("1 error")
    end

    it "selects the plural form" do
      expect(helper.red_tp("red.count_probe", count: 5)).to eq("5 errors")
    end

    it "uses the plural form for zero" do
      expect(helper.red_tp("red.count_probe", count: 0)).to eq("0 errors")
    end

    [ 0, 1, 2, 5, 11, 21, 100 ].each do |count|
      it "returns a String for count #{count}" do
        expect(helper.red_tp("red.count_probe", count: count)).to be_a(String)
      end
    end

    it "does not raise when the locale lacks the needed plural category" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { other_only_probe: { other: "%{count} things" } }
      )

      expect { helper.red_tp("red.other_only_probe", count: 1) }.not_to raise_error
    end
  end

  describe "#red_locale" do
    it "returns the configured locale" do
      expect(helper.red_locale).to eq("en")
    end

    it "prefers the request-scoped locale" do
      RailsErrorDashboard::Current.locale = "en"

      expect(helper.red_locale).to eq("en")
    end

    it "returns a shipped locale even when configuration is nonsense" do
      RailsErrorDashboard.configuration.dashboard_locale = "zz"

      expect(helper.red_locale).to eq("en")
    end
  end

  describe "#red_time_format" do
    it "returns the strftime pattern for a known preset" do
      expect(helper.red_time_format(:full)).to eq("%B %d, %Y %I:%M:%S %p")
    end

    it "returns a usable strftime pattern for every preset" do
      %i[full short date_only time_only datetime].each do |preset|
        pattern = helper.red_time_format(preset)

        expect(pattern).to include("%")
        expect { Time.now.utc.strftime(pattern) }.not_to raise_error
      end
    end

    it "falls back to a valid pattern for an unknown preset" do
      pattern = helper.red_time_format(:no_such_preset)

      expect(pattern).to include("%")
      expect { Time.now.utc.strftime(pattern) }.not_to raise_error
    end

    it "only uses directives the browser-side formatter supports" do
      # data-format is re-rendered by formatDateTime() in the layout, which
      # implements a fixed directive set. A pattern using anything else would
      # render literally in the browser.
      supported = %w[%Y %y %B %b %m %d %e %A %a %H %I %M %S %p %P]

      %i[full short date_only time_only datetime].each do |preset|
        directives = helper.red_time_format(preset).scan(/%[a-zA-Z]/)

        expect(directives - supported).to be_empty,
          "#{preset} uses directives the JS formatter cannot render: #{(directives - supported).inspect}"
      end
    end
  end

  # red_t html-escapes, which is right for page text and wrong inside a JS
  # string literal. The two sinks in the layout's script blocks disagree about
  # entities: showToast and innerHTML decode &#39; back to an apostrophe, but
  # textContent renders it literally, so a French string would display
  # "d&#39;accéder" on screen. red_js_t escapes for the literal instead.
  describe "#red_js_t" do
    let(:backslash) { 92.chr }

    it "escapes an apostrophe for the literal rather than into an entity" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js_escape_probe: "Copié dans l'presse-papiers" }
      )

      result = helper.red_js_t("red.js_escape_probe")

      expect(result).to eq("Copié dans l#{backslash}'presse-papiers")
      expect(result).not_to include("&#39;")
    end

    # The real job: an unescaped quote closes the literal and everything after
    # it is parsed as code.
    it "escapes quotes so a value cannot break out of the literal" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js_escape_probe: "it's done'; alert(1); var x='" }
      )

      result = helper.red_js_t("red.js_escape_probe")

      expect(result).to eq("it#{backslash}'s done#{backslash}'; alert(1); var x=#{backslash}'")
      expect(result).not_to include("done'; alert(1)")
    end

    it "escapes a newline that would otherwise truncate the statement" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js_escape_probe: "line one\nline two" }
      )

      result = helper.red_js_t("red.js_escape_probe")

      expect(result).to eq("line one#{backslash}nline two")
      expect(result).not_to include("\n")
    end

    it "returns readable text for a missing key rather than raising" do
      expect(helper.red_js_t("red.nope.absent_js_key")).to eq("Absent js key")
    end

    # escape_javascript comes from ActionView. In a request the controller
    # mixes every engine helper into one view context so it happens to be
    # present, but that is incidental — this asserts the explicit include,
    # without which every red_js_t site silently rendered an empty string.
    it "has escape_javascript available without relying on the view context" do
      bare = Class.new { include RailsErrorDashboard::I18nHelper }.new

      expect(bare).to respond_to(:escape_javascript)
    end

    it "pluralizes through red_js_tp" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js_plural_probe: { one: "1 thing", other: "%{count} things" } }
      )

      expect(helper.red_js_tp("red.js_plural_probe", count: 1)).to eq("1 thing")
      expect(helper.red_js_tp("red.js_plural_probe", count: 5)).to eq("5 things")
    end
  end

  describe "#red_js_translations" do
    it "returns the JS subtree, the time formats, and the locale" do
      payload = helper.red_js_translations

      expect(payload.keys).to match_array(%w[locale js formats ago])
      expect(payload["locale"]).to eq("en")
      expect(payload["js"][:months].first).to eq("January")
      expect(payload["formats"][:full]).to eq("%B %d, %Y %I:%M:%S %p")

      # Shared with the server's local_time_ago rather than duplicated, so both
      # sides place "ago" wherever the language wants it.
      expect(payload["ago"]).to eq("%{duration} ago")
    end

    # REQ-1. This ships on every page load, so the guard is on what it does NOT
    # contain — the dictionary is ~1,350 keys and growth here is silent.
    it "does not ship the server-rendered namespaces" do
      payload = helper.red_js_translations

      expect(payload).not_to have_key("nav")
      expect(payload).not_to have_key("errors")
      expect(payload).not_to have_key("settings")
      expect(payload).not_to have_key("flash")
    end

    it "reports the request's locale, not always English" do
      RailsErrorDashboard::Current.locale = "en"

      expect(helper.red_js_translations["locale"]).to eq("en")
    end

    # Built in the layout, so a raise here would take down every page rather
    # than degrade one string.
    it "returns a hash rather than raising when the store fails" do
      allow(RailsErrorDashboard::I18nStore).to receive(:subtree).and_raise(StandardError, "boom")

      expect { helper.red_js_translations }.not_to raise_error
      expect(helper.red_js_translations).to eq({})
    end

    # Values are consumed as JS strings after JSON serialization. ERB escaping
    # here would surface literal &amp;amp; in the browser.
    it "returns raw values, not html-escaped ones" do
      RailsErrorDashboard::I18nStore.backend.store_translations(
        :en, red: { js: { amp_probe: "Search & filter" } }
      )

      expect(helper.red_js_translations["js"][:amp_probe]).to eq("Search & filter")
    ensure
      RailsErrorDashboard::I18nStore.reset!
    end
  end
end
