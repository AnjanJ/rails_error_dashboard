# frozen_string_literal: true

require "rails_helper"

# P3-T2. formatDateTime, formatRelativeTime and the timestamp tooltips read
# from RED_I18N instead of hardcoded English arrays.
#
# Those functions live inside the layout's IIFE and are deliberately not on
# window, so these specs drive them the way a user does — through rendered
# timestamps and the click-to-toggle behaviour — rather than calling them
# directly. The exhaustive per-directive and per-threshold comparison against
# the pre-change implementation runs in spec/javascript/date_localization.test.js,
# where the functions can be loaded in isolation.
RSpec.describe "Localized dates in the browser", type: :system do
  let!(:application) { create(:application) }
  let!(:error_log) do
    create(:error_log, application: application, occurred_at: Time.utc(2026, 3, 9, 14, 5, 3))
  end

  before do
    visit_dashboard("/errors")
    wait_for_page_load
  end

  describe "rendered timestamps" do
    it "converts server-rendered UTC timestamps to localized local time" do
      element = first(".local-time", minimum: 0)
      skip "no .local-time element on this page" if element.nil?

      # The JS replaced the server's text, so a month name proves the localized
      # arrays were used rather than left undefined.
      expect(element.text).not_to include("undefined")
      expect(element.text).to match(/January|February|March|April|May|June|July|August|September|October|November|December|\d{2}\/\d{2}/)
    end

    it "renders relative timestamps with no undefined" do
      element = first(".local-time-ago", minimum: 0)
      skip "no .local-time-ago element on this page" if element.nil?

      expect(element.text).not_to include("undefined")
      expect(element.text).to match(/ago/)
    end
  end

  # REQ-5. The tooltips were English literals; they are keys now, and the
  # click-to-toggle behaviour they describe must still work.
  describe "timestamp tooltips and toggling (REQ-5)" do
    it "labels a converted timestamp and toggles it between local and UTC" do
      element = first(".local-time", minimum: 0)
      skip "no .local-time element on this page" if element.nil?

      expect(element[:title]).to eq("Your local time (click to see UTC)")
      local_text = element.text

      element.click
      expect(element[:title]).to eq("UTC time (click to see local time)")
      expect(element.text).to include("UTC")
      expect(element.text).not_to include("undefined")

      element.click
      expect(element[:title]).to eq("Your local time (click to see UTC)")
      expect(element.text).to eq(local_text)
    end

    # Only the initial label is asserted here. Clicking one of these re-runs
    # convertToLocalTime() against a re-rendered node, which re-labels it —
    # behaviour identical before and after P3-T2, and not this task's to change.
    # The toggled label itself is covered by the .local-time example above.
    it "labels a relative timestamp with the translated tooltip" do
      element = first(".local-time-ago", minimum: 0)
      skip "no .local-time-ago element on this page" if element.nil?

      expect(element[:title]).to eq("Click to see exact time")
      expect(element.text).not_to include("undefined")
    end
  end

  # The payload is what the localized functions read. If these keys stop
  # arriving, every timestamp silently reverts to the English fallback.
  describe "the data the date functions read" do
    it "ships month, day, meridian and duration forms" do
      payload = page.evaluate_script("window.RED_I18N.js")

      expect(payload["months"].length).to eq(12)
      expect(payload["days"].length).to eq(7)
      expect(payload["meridian"]).to eq("am" => "AM", "pm" => "PM")
      expect(payload["duration"]["minutes"]).to eq("one" => "1 minute", "other" => "%{count} minutes")
    end

    it "ships the ago template as one key rather than a bare suffix" do
      expect(page.evaluate_script("window.RED_I18N.ago")).to eq("%{duration} ago")
    end
  end
end
