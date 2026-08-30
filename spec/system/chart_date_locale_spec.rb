# frozen_string_literal: true

require "rails_helper"

# #178. Chart.js renders date axes through chartjs-adapter-date-fns, whose
# bundle carries English locale data only, so every locale's charts read
# "Aug 6". Reported by a contributor reviewing the French locale.
#
# This has to run in a real browser: the fix patches the adapter's format() on
# the prototype, and the only way to know a chart axis actually changed is to
# ask Chart.js what it drew. A request spec can only see the JS source.
RSpec.describe "Chart date axes follow the dashboard locale", type: :system do
  let!(:application) { create(:application) }

  before do
    # Two weeks of errors so the trend chart has a real day axis.
    14.times do |i|
      create(:error_log, application: application, occurred_at: (i + 1).days.ago)
    end
  end

  around do |example|
    original = RailsErrorDashboard.configuration.dashboard_locale
    example.run
  ensure
    RailsErrorDashboard.configuration.dashboard_locale = original
    # Current is request-scoped but survives between examples in the test
    # process. Leaving a locale set here made js_date_localization's
    # `.local-time` assertions skip when this file happened to run first.
    RailsErrorDashboard::Current.locale = nil
  end

  # The adapter is what turns a timestamp into an axis label. Asking it
  # directly is both stabler than scraping canvas pixels and closer to the
  # defect: the old code returned "Aug 6" here for every locale.
  def adapter_day_label
    page.evaluate_script(<<~JS)
      (function() {
        if (typeof Chart === 'undefined' || !Chart._adapters || !Chart._adapters._date) return null;
        var a = new Chart._adapters._date({});
        return a.format(Date.UTC(2026, 7, 6), 'MMM d');
      })();
    JS
  end

  it "formats a chart date in English under the default locale" do
    RailsErrorDashboard.configuration.dashboard_locale = "en"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    label = adapter_day_label
    skip "Chart.js not loaded on this page" if label.nil?

    expect(label).to include("Aug")
  end

  it "formats the same date with the locale's own month name in French" do
    RailsErrorDashboard.configuration.dashboard_locale = "fr"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    label = adapter_day_label
    skip "Chart.js not loaded on this page" if label.nil?

    expected = RailsErrorDashboard::Services::LocalizedTimeFormatter.call(
      Time.utc(2026, 8, 6), pattern: "%b", locale: "fr"
    )

    # The bug: this read "Aug" in every locale.
    expect(label).not_to include("Aug")
    expect(label).to include(expected)
    expect(label).not_to include("undefined")

    # #178 round 2: the words alone are not enough. "août 06" satisfies every
    # assertion above and is still wrong — French writes the day first.
    expect(label).to eq("6 août")
  end

  # The same axis in a locale whose date order is not merely reversed but
  # structurally different, so a fix that only swapped two fields would fail.
  it "renders the day axis in year-month-day order for Japanese" do
    RailsErrorDashboard.configuration.dashboard_locale = "ja"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    label = adapter_day_label
    skip "Chart.js not loaded on this page" if label.nil?

    expect(label).to eq("8月6日")
  end

  # Chartkick does not use the adapter's format table as-is: for hour and minute
  # granularity it overrides displayFormats and tooltipFormat with patterns of
  # its own. Those were absent from TOKENS, so an hour axis and every tooltip on
  # it stayed English even once the day axis had been translated — the gap that
  # survived the first fix.
  def adapter_label(pattern, at: Date.new(2026, 8, 6))
    page.evaluate_script(<<~JS)
      (function() {
        if (typeof Chart === 'undefined' || !Chart._adapters || !Chart._adapters._date) return null;
        var a = new Chart._adapters._date({});
        return a.format(Date.UTC(#{at.year}, #{at.month - 1}, #{at.day}, 15, 4), '#{pattern}');
      })();
    JS
  end

  {
    "MMM d, h a" => "hour tick and tooltip",
    "h:mm a" => "minute tick and tooltip"
  }.each do |pattern, what|
    it "localizes Chartkick's own #{what} pattern" do
      RailsErrorDashboard.configuration.dashboard_locale = "fr"

      visit_dashboard("/errors/analytics")
      wait_for_page_load

      label = adapter_label(pattern)
      skip "Chart.js not loaded on this page" if label.nil?

      # French declares a 24-hour clock in its own time_only, so an axis must
      # not read "3 PM" — and must certainly not carry an English meridian.
      #
      # The hour itself is deliberately not asserted: formatDateTime reads local
      # time, so the value depends on the machine's zone. What matters is the
      # shape — 24-hour, no meridian.
      expect(label).not_to include("PM")
      expect(label).not_to include("AM")
      expect(label).to match(/\d{2}:\d{2}/)
    end
  end

  it "uses the locale's own hour format rather than a 12-hour clock" do
    RailsErrorDashboard.configuration.dashboard_locale = "fr"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    label = adapter_label("ha")
    skip "Chart.js not loaded on this page" if label.nil?

    # fr's axis_hour is "%Hh" — a 24-hour number and the French hour suffix,
    # never "3 PM".
    expect(label).to match(/\A\d{2}h\z/)
  end

  it "leaves a pattern it does not recognize to the original adapter" do
    RailsErrorDashboard.configuration.dashboard_locale = "fr"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    result = page.evaluate_script(<<~JS)
      (function() {
        if (typeof Chart === 'undefined' || !Chart._adapters || !Chart._adapters._date) return null;
        var a = new Chart._adapters._date({});
        return a.format(Date.UTC(2026, 7, 6), 'yyyy-MM-dd');
      })();
    JS
    skip "Chart.js not loaded on this page" if result.nil?

    # Not in the token map, so date-fns still handles it — and must not throw.
    expect(result).to eq("2026-08-06")
  end
end
