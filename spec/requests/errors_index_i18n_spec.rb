# frozen_string_literal: true

require "rails_helper"

# The errors index is the dashboard's landing page and carries the filter bar,
# which is where extraction was most likely to change behaviour rather than
# just move strings. These specs pin the properties a mechanical wrap would
# quietly break: the machine-valued filters no longer go through English
# morphology, an unrecognised value still renders, and the interpolated
# markup keys are not escaped into visible tags.
RSpec.describe "Errors index translations", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "page furniture" do
    it "renders the heading and column labels" do
      create(:error_log, application: application)

      get "/error_dashboard/errors"

      expect(response.body).to include("Errors")
      expect(response.body).to include(">Events<")
      expect(response.body).to include(">Last seen<")
    end

    it "keeps the local-time markup intact in the last-updated line" do
      get "/error_dashboard/errors"

      # last_updated_html interpolates a <span class="local-time"> element.
      # Escaping it would print the tag as visible text.
      expect(response.body).to include("Last updated:")
      expect(response.body).to match(/Last updated:\s*<span class="local-time"/)
      expect(response.body).not_to include("Last updated: &lt;span")
    end
  end

  describe "summary line" do
    it "interpolates the styled count without escaping its markup" do
      create_list(:error_log, 2, application: application)

      get "/error_dashboard/errors"

      expect(response.body).to match(%r{<strong style="color: var\(--text-primary\);">2</strong> errors})
      expect(response.body).not_to include("&lt;strong")
    end

    it "uses the singular form for one error" do
      create(:error_log, application: application)

      get "/error_dashboard/errors"

      expect(response.body).to match(%r{</strong> error\b})
      expect(response.body).not_to match(%r{>1</strong> errors})
    end
  end

  # REQ-A. These four filters carry machine values. humanize/titleize/capitalize
  # applied English morphology to them, which is nonsense in any other language.
  describe "machine-valued filters (REQ-A)" do
    it "labels a timeframe from a key rather than humanizing the param" do
      get "/error_dashboard/errors", params: { timeframe: "last_7_days" }

      expect(response.body).to include("Last 7 Days")
      # What humanize would have produced.
      expect(response.body).not_to include("Last 7 days")
    end

    it "labels a frequency from a key rather than humanizing the param" do
      get "/error_dashboard/errors", params: { frequency: "very_frequent" }

      expect(response.body).to include("100+ Times")
      expect(response.body).not_to include("Very frequent")
    end

    it "labels a status from a key rather than humanizing the param" do
      get "/error_dashboard/errors", params: { status: "resolved" }

      expect(response.body).to include("Status: Resolved")
    end

    it "renders the same label in the select and in the chip it produces" do
      get "/error_dashboard/errors", params: { timeframe: "last_30_days" }

      # Once as the selected <option>, once inside the active chip. Building
      # both from the same key is what keeps them in agreement.
      expect(response.body.scan("Last 30 Days").size).to be >= 2
    end

    it "does not raise on an unrecognised value and falls back to the raw text" do
      get "/error_dashboard/errors", params: { timeframe: "nonsense_value", frequency: "zzz" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("nonsense_value")
    end
  end

  # REQ-B/REQ-C. The label around a value is translated; the value itself is
  # user data and is not.
  describe "filter chips (REQ-B, REQ-C)" do
    it "interpolates a search term verbatim rather than translating it" do
      get "/error_dashboard/errors", params: { search: "NoMethodError" }

      expect(response.body).to include("Search: NoMethodError")
    end

    it "escapes a search term containing markup exactly once" do
      get "/error_dashboard/errors", params: { search: "<script>x</script>" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<script>x</script>")
      # Escaped once, not twice — &amp;lt; would be a double-escape bug.
      expect(response.body).not_to include("&amp;lt;script")
    end

    it "shows the priority short label rather than the raw integer" do
      get "/error_dashboard/errors", params: { priority_level: "3" }

      expect(response.body).to include("Priority: P0")
      expect(response.body).not_to include("Priority: 3")
    end
  end

  describe "empty states" do
    it "renders the all-clear state when nothing has been logged" do
      get "/error_dashboard/errors"

      expect(response.body).to include("All clear!")
    end

    it "renders the filtered state when a filter matches nothing" do
      get "/error_dashboard/errors", params: { search: "no-such-error-anywhere" }

      expect(response.body).to include("No errors match your filters")
      expect(response.body).to include("Clear all filters")
    end
  end

  describe "error row" do
    it "translates the workflow status while keeping the colour keyed on the raw value" do
      create(:error_log, application: application, status: "in_progress", resolved: false)

      get "/error_dashboard/errors"

      # "in progress" is the translated label; the colour lookup uses
      # "in_progress", so the info colour must still be applied.
      expect(response.body).to include("in progress")
      expect(response.body).to include("var(--status-info)")
    end

    # severity is derived from error_type by SeverityClassifier, not stored.
    it "renders a translated severity label rather than the raw symbol" do
      create(:error_log, application: application, error_type: "SecurityError")

      get "/error_dashboard/errors"

      expect(response.body).to include("Critical")
    end

    # user_id is an integer column, so the id is a number rather than a name.
    it "titles the user link with the user id interpolated, not concatenated" do
      create(:error_log, application: application, user_id: 42)

      get "/error_dashboard/errors"

      expect(response.body).to include('title="View all errors for user 42"')
    end
  end
end
