# frozen_string_literal: true

require "rails_helper"

# The seven remaining dashboard pages (P2-T9). These pin the parts that were not
# mechanical: a threshold that was written twice, machine values that were being
# echoed raw, units glued onto numbers, and the sentences that were assembled
# from fragments around markup.
RSpec.describe "Summary page translations", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  def body_doc
    Nokogiri::HTML(response.body)
  end

  # Enable a config flag for the duration of the block and restore it.
  def with_config(**attrs)
    config = RailsErrorDashboard.configuration
    was = attrs.keys.to_h { |k| [ k, config.send(k) ] }
    attrs.each { |k, v| config.send("#{k}=", v) }
    yield
  ensure
    was.each { |k, v| config.send("#{k}=", v) }
  end

  describe "overview" do
    it "renders the page heading and stat labels" do
      get "/error_dashboard/overview"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Overview")
      expect(body).to include("Error Rate")
      expect(body).to include("Resolution Rate")
      expect(body).to include("Mean time to resolution")
    end

    # The tab title and the h1 are different strings ("Dashboard" vs
    # "Overview"). Collapsing them into one key silently renamed the browser tab.
    it "keeps the browser tab title distinct from the page heading" do
      get "/error_dashboard/overview"

      doc = body_doc
      expect(doc.at_css("title").text).to include("Dashboard")
      expect(doc.at_css("h1").text.strip).to eq("Overview")
    end

    # The banner used a ? 's' : '' ternary, which assumes English's binary
    # plural. It is a red_tp key now.
    it "uses the singular alert banner for a single critical error" do
      # CriticalAlerts filters on priority_level 3/4 and an unresolved error
      # within the last hour — not on the derived severity.
      create(:error_log, application: application, error_type: "SecurityError",
             priority_level: 4, resolved_at: nil, occurred_at: 10.minutes.ago)

      get "/error_dashboard/overview"

      body = response.body
      expect(body).to include("1 Critical/High Error in Last Hour")
      expect(body).not_to include("1 Critical/High Errors in Last Hour")
    end

    it "uses the plural alert banner for several critical errors" do
      2.times do |i|
        create(:error_log, application: application, error_type: "SecurityError",
               message: "distinct boom #{i}", priority_level: 4,
               resolved_at: nil, occurred_at: 10.minutes.ago)
      end

      get "/error_dashboard/overview"

      expect(response.body).to match(/[2-9]\d* Critical\/High Errors in Last Hour/)
    end

    # "X of Y resolved" was three fragments in one <small>.
    it "renders the resolution hint as one phrase" do
      get "/error_dashboard/overview"

      expect(response.body).to match(/\d+ of \d+ resolved/)
    end

    # CSS text-transform: capitalize was applied to the platform value, which is
    # a brand name stored already-cased. Capitalize renders "iOS" as "IOS".
    it "does not apply CSS capitalization to platform names" do
      create(:error_log, :ios, application: application)

      # The platform health block is gated on this flag; without it the tile
      # never renders and the assertion would pass vacuously.
      with_config(enable_platform_comparison: true) do
        get "/error_dashboard/overview"

        expect(response.body).to include("Platform Health")
        expect(response.body).to include("iOS")
        expect(response.body).not_to include("text-transform: capitalize")
      end
    end
  end

  describe "storms" do
    it "renders the page and its column headers" do
      RailsErrorDashboard::StormEvent.create!(
        started_at: 2.hours.ago, ended_at: 1.hour.ago,
        peak_rate_per_minute: 1_200, reached_open: true,
        events_counted_only: 500, events_overflow: 20,
        top_fingerprints: [ { "class" => "SecurityError", "message" => "boom", "count" => 42 } ].to_json
      )

      get "/error_dashboard/errors/storms"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Storm History")
      expect(body).to include("Peak Rate")
      expect(body).to include("Counted (exact)")
    end

    # The mode badges were raw English words; they are keys now. The rate unit
    # was glued onto the number.
    it "renders the mode badge and the rate unit through keys" do
      RailsErrorDashboard::StormEvent.create!(
        started_at: 2.hours.ago, ended_at: 1.hour.ago,
        peak_rate_per_minute: 1_200, reached_open: true,
        top_fingerprints: [].to_json
      )

      get "/error_dashboard/errors/storms"

      expect(response.body).to include("count-only")
      expect(response.body).to include("1,200/min")
    end

    # The intro wrapped prose around a <code> element naming a config prefix.
    it "keeps the config option prefix in a code element" do
      get "/error_dashboard/errors/storms"

      expect(response.body).to include("<code>storm_*</code>")
      expect(response.body).not_to include("&lt;code&gt;storm_*")
    end

    it "renders the empty state when no storms exist" do
      get "/error_dashboard/errors/storms"

      expect(response.body).to include("No Storms Recorded")
    end
  end

  describe "deprecations" do
    around { |ex| with_config(enable_breadcrumbs: true) { ex.run } }

    it "renders the page and reuses the shared day filter" do
      get "/error_dashboard/errors/deprecations"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Deprecation Warnings")
      expect(body).to include("7 Days")
      expect(body).to include("90 Days")
    end

    # The config option name is an identifier and stays inside <code>.
    it "keeps the config option name in the how-it-works list" do
      get "/error_dashboard/errors/deprecations"

      expect(response.body).to include("<code>enable_breadcrumbs = true</code>")
      expect(response.body).not_to include("&lt;code&gt;enable_breadcrumbs")
    end

    it "interpolates the day range into the empty state" do
      get "/error_dashboard/errors/deprecations?days=7"

      expect(response.body).to include("over the last 7 days")
    end
  end

  describe "n+1 summary" do
    around { |ex| with_config(enable_breadcrumbs: true) { ex.run } }

    # The prose said "Default threshold is 3 repetitions" with a hardcoded 3,
    # duplicating configuration.rb's default. It reads the config now, so the
    # sentence cannot drift from the value actually applied.
    it "reads the default threshold from the configuration" do
      with_config(n_plus_one_threshold: 7) do
        get "/error_dashboard/errors/n_plus_one_summary"

        expect(response.body).to include("Default threshold is 7 repetitions")
        expect(response.body).not_to include("Default threshold is 3")
      end
    end

    it "uses the singular form when the threshold is one" do
      with_config(n_plus_one_threshold: 1) do
        get "/error_dashboard/errors/n_plus_one_summary"

        expect(response.body).to include("Default threshold is 1 repetition")
        expect(response.body).not_to include("1 repetitions")
      end
    end

    # These three strings already existed for the detail panel; the summary page
    # reuses them rather than minting near-duplicates.
    it "reuses the detail panel's column and guide keys" do
      get "/error_dashboard/errors/n_plus_one_summary"

      # With no patterns the empty state renders; the reused table keys are
      # asserted directly against the store so this does not depend on fixtures.
      expect(response.body).to include("How N+1 detection works:")
      expect(RailsErrorDashboard::I18nStore.translate("red.errors.n_plus_one.column_query", locale: "en"))
        .to eq("Query Pattern")
      expect(RailsErrorDashboard::I18nStore.translate("red.errors.n_plus_one.column_total_time", locale: "en"))
        .to eq("Total Time")
      expect(RailsErrorDashboard::I18nStore.translate("red.errors.n_plus_one.eager_loading_guide", locale: "en"))
        .to eq("Rails Eager Loading Guide")
    end
  end

  describe "swallowed exceptions" do
    around { |ex| with_config(detect_swallowed_exceptions: true) { ex.run } }

    it "renders the page and its column headers" do
      create(:swallowed_exception, :fully_swallowed, application: application)

      get "/error_dashboard/errors/swallowed_exceptions"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Swallowed Exceptions")
      expect(body).to include("Exception Class")
      expect(body).to include("Raise Location")
    end

    # The tooltip built a sentence around an interpolated exception class.
    it "interpolates the exception class into the row tooltip" do
      create(:swallowed_exception, :fully_swallowed, application: application,
             exception_class: "Stripe::CardError")

      get "/error_dashboard/errors/swallowed_exceptions"

      expect(response.body).to include("View any unrescued Stripe::CardError errors")
    end

    # The threshold comes from config, so the prose tracks the real value.
    it "interpolates the configured rescue-ratio threshold" do
      with_config(swallowed_exception_threshold: 0.8) do
        get "/error_dashboard/errors/swallowed_exceptions"

        expect(response.body).to include("rescue ratio above 80%")
      end
    end

    # TracePoint(:raise) is a Ruby API and survives translation verbatim.
    it "keeps the Ruby API names in the how-it-works list" do
      get "/error_dashboard/errors/swallowed_exceptions"

      expect(response.body).to include("TracePoint(:raise)")
      expect(response.body).to include("TracePoint(:rescue)")
    end
  end

  describe "rate limit events" do
    around { |ex| with_config(enable_rack_attack_tracking: true) { ex.run } }

    it "renders the page and its stat labels" do
      get "/error_dashboard/errors/rack_attack_summary"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Rate Limit Events")
      # No events recorded, so the empty state renders.
      expect(body).to include("How Rack Attack tracking works:")
    end

    # The flush interval is read from config rather than restated in prose.
    it "interpolates the configured flush interval" do
      with_config(rack_attack_flush_interval: 45) do
        get "/error_dashboard/errors/rack_attack_summary"

        expect(response.body).to include("written every 45s")
      end
    end
  end

  describe "diagnostic dumps" do
    around { |ex| with_config(enable_diagnostic_dump: true) { ex.run } }

    it "renders the page and its section labels" do
      get "/error_dashboard/errors/diagnostic_dumps"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Diagnostic Dumps")
      expect(body).to include("Capture Dump")
    end

    # The instruction named the button by repeating its label. It interpolates
    # the button's own key now, so the two cannot drift apart.
    it "names the capture button by interpolating its label" do
      get "/error_dashboard/errors/diagnostic_dumps"

      expect(response.body).to include("<strong>Capture Dump</strong>")
    end

    it "keeps the rake command in a code element" do
      get "/error_dashboard/errors/diagnostic_dumps"

      expect(response.body).to include("<code>rails error_dashboard:diagnostic_dump</code>")
      expect(response.body).not_to include("&lt;code&gt;rails error_dashboard")
    end
  end
end
