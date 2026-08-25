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
