# frozen_string_literal: true

require "rails_helper"

# #178, round 2. The layout registered both of its `chartkick:load` handlers on
# `document`, but Chartkick dispatches
#
#   window.dispatchEvent(new Event("chartkick:load"))
#
# on `window`, and a bare `Event` has `bubbles: false`. A non-bubbling event
# dispatched on window never reaches a document listener, so BOTH handlers were
# dead code from the day they were written:
#
#   * applyChartTheme() never re-ran when charts finished loading
#   * installRedChartDateAdapter()'s re-assert never fired, which is half of why
#     a clobbered date adapter could never repair itself
#
# Neither failure is visible on screen — the theme usually looks right because a
# MutationObserver also applies it, and the date adapter usually wins its race.
# That is exactly why this needs a test: the symptom of a listener that never
# fires is nothing at all.
#
# These specs therefore assert on RED's OWN handler running. An earlier draft
# dispatched the event and counted a listener the spec itself registered, which
# passed against the broken code — it was testing the DOM, not the wiring.
RSpec.describe "chartkick:load listeners", type: :system do
  let!(:application) { create(:application) }

  before do
    create(:error_log, application: application, occurred_at: 1.day.ago)
  end

  # Current is request-scoped but survives between examples in the test process;
  # leaving a locale set here makes unrelated specs assert against the wrong one.
  around do |example|
    original = RailsErrorDashboard.configuration.dashboard_locale
    example.run
  ensure
    RailsErrorDashboard.configuration.dashboard_locale = original
    RailsErrorDashboard::Current.locale = nil
  end

  # Undo the date-adapter patch, then dispatch the event exactly as Chartkick
  # 5.0.1 does — same constructor, same target. A live re-assert handler
  # reinstalls the patch; a handler registered on `document` never runs and
  # leaves the adapter unpatched.
  #
  # Asserts on the rendered label rather than on any bookkeeping property: what
  # matters is that a chart axis reads "août", and a flag saying the patch is
  # installed is exactly the kind of evidence that was wrong in #178 round 2.
  #
  # Returns nil when Chart.js is absent so the caller can skip rather than fail
  # on an unrelated asset problem.
  def label_after_stripping_patch_and_firing_chartkick_load
    page.evaluate_script(<<~JS)
      (function() {
        if (typeof Chart === 'undefined' || !Chart._adapters || !Chart._adapters._date) return null;
        var proto = Chart._adapters._date.prototype;

        // Stand in for chartjs-adapter-date-fns winning the load race: replace
        // format() wholesale, exactly as its Object.assign(prototype, …) does.
        proto.format = function(time, fmt) { return 'UNPATCHED'; };

        window.dispatchEvent(new Event('chartkick:load'));

        return proto.format.call({ options: {} }, Date.UTC(2026, 7, 6), 'MMM d');
      })();
    JS
  end

  it "re-asserts the date adapter when Chartkick announces it has loaded" do
    RailsErrorDashboard.configuration.dashboard_locale = "fr"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    label = label_after_stripping_patch_and_firing_chartkick_load
    skip "Chart.js not loaded on this page" if label.nil?

    # "UNPATCHED" means the handler never ran: it was registered on a target the
    # event does not reach. "Aug 06" would mean it ran but refused to reinstall,
    # which is what the old _redPatched flag did after being clobbered.
    expect(label).not_to eq("UNPATCHED")
    expect(label).to include("août")
  end

  # The reported symptom (#178 round 2): "on wide screen I get English month
  # names while on narrow screen I get French ones" — same page, same dates.
  # Screen width was a red herring; the two loads simply resolved three CDN
  # scripts in different orders.
  #
  # Reinstalling twice in a row must also be safe. The old flag made the second
  # call a no-op; an identity check has to stay a no-op without nesting wrappers
  # around each other, or a chart would pay for one delegation per page event.
  it "survives the adapter overwriting format(), and re-asserts idempotently" do
    RailsErrorDashboard.configuration.dashboard_locale = "fr"

    visit_dashboard("/errors/analytics")
    wait_for_page_load

    result = page.evaluate_script(<<~JS)
      (function() {
        if (typeof Chart === 'undefined' || !Chart._adapters || !Chart._adapters._date) return null;
        var proto = Chart._adapters._date.prototype;

        proto.format = function(time, fmt) { return 'UNPATCHED'; };
        window.dispatchEvent(new Event('chartkick:load'));
        var repaired = proto.format.call({ options: {} }, Date.UTC(2026, 7, 6), 'MMM d');

        // Two further re-asserts with nothing broken in between.
        var afterFirst = proto.format;
        window.dispatchEvent(new Event('chartkick:load'));
        window.dispatchEvent(new Event('chartkick:load'));

        return {
          repaired: repaired,
          stable: proto.format === afterFirst,
          label: proto.format.call({ options: {} }, Date.UTC(2026, 7, 6), 'MMM d')
        };
      })();
    JS
    skip "Chart.js not loaded on this page" if result.nil?

    expect(result["repaired"]).to include("août")
    expect(result["stable"]).to be(true)
    expect(result["label"]).to include("août")
  end

  # applyChartTheme() is the handler whose deadness nobody reported. It writes
  # Chart.defaults.color, so a live handler is observable the same way: clobber
  # the value, fire the event, and see whether RED puts it back.
  it "re-applies the chart theme when Chartkick announces it has loaded" do
    visit_dashboard("/errors/analytics")
    wait_for_page_load

    restored = page.evaluate_script(<<~JS)
      (function() {
        if (typeof Chart === 'undefined' || !Chart.defaults) return null;
        Chart.defaults.color = '__CLOBBERED__';
        window.dispatchEvent(new Event('chartkick:load'));
        return Chart.defaults.color !== '__CLOBBERED__';
      })();
    JS
    skip "Chart.js not loaded on this page" if restored.nil?

    expect(restored).to be(true)
  end
end
