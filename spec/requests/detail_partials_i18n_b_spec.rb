# frozen_string_literal: true

require "rails_helper"

# Second half of the detail page's partials (P2-T7b). These pin the cases that
# were not mechanical: sentences that wrapped around <code> elements, provider
# brand names that capitalize was mangling, thresholds cited in prose as well as
# in code, and the pluralization hacks the extraction replaced.
RSpec.describe "Detail partial translations (part 2)", type: :request do
  let!(:application) { create(:application) }
  let!(:error) do
    create(:error_log, application: application, error_type: "SecurityError",
           occurrence_count: 3)
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "issue tracker" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_issue_tracking
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_issue_tracking = was
    end

    it "renders the section labels" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Issue Tracker")
      expect(response.body).to include("Create New Issue")
      expect(response.body).to include("Link Existing Issue")
    end

    # The config option names are identifiers; only the sentence is translated.
    it "keeps the config option names in code tags inside the setup hint" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("<code>issue_tracker_token</code>")
      expect(response.body).to include("<code>git_repository_url</code>")
      expect(response.body).to include("in your initializer to enable issue creation.")
      expect(response.body).not_to include("&lt;code&gt;issue_tracker_token")
    end

    # "github".capitalize is "Github", which is not the brand's own casing.
    it "renders the provider's brand casing in the issue badge" do
      error.update_columns(external_issue_provider: "github",
                           external_issue_number: 42,
                           external_issue_url: "https://github.com/o/r/issues/42")

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("GitHub #42")
      expect(response.body).not_to include("Github #42")
    end
  end

  describe "discussion" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_issue_tracking
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_issue_tracking = was
    end

    it "interpolates the provider's brand name into the call to action" do
      error.update_columns(external_issue_provider: "gitlab",
                           external_issue_url: "https://gitlab.com/o/r/issues/1")

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Start discussion on GitLab")
      expect(response.body).not_to include("Start discussion on Gitlab")
    end
  end

  describe "N+1 detection" do
    # The N+1 card lives inside the breadcrumbs partial, so it needs the
    # breadcrumbs master switch as well as its own.
    around do |example|
      was_n1 = RailsErrorDashboard.configuration.enable_n_plus_one_detection
      was_crumbs = RailsErrorDashboard.configuration.enable_breadcrumbs
      RailsErrorDashboard.configuration.enable_n_plus_one_detection = true
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_n_plus_one_detection = was_n1
      RailsErrorDashboard.configuration.enable_breadcrumbs = was_crumbs
    end

    let(:crumbs) do
      Array.new(4) do |i|
        { "c" => "sql", "m" => "SELECT * FROM posts WHERE user_id = #{i}", "d" => 5 }
      end
    end

    it "renders the tip with method names in code tags, not escaped" do
      error.update_column(:breadcrumbs, crumbs.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Tip:")
      expect(response.body).to match(%r{<code>\.(includes|preload)})
      expect(response.body).not_to include("&lt;code&gt;.includes")
    end
  end

  describe "occurrence patterns" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_occurrence_patterns
      RailsErrorDashboard.configuration.enable_occurrence_patterns = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_occurrence_patterns = was
    end

    # The window is named once and cited in the heading, so the prose cannot
    # drift from the query that produced the data.
    it "renders the analysis window from the same value the query uses" do
      create_list(:error_log, 3, application: application, error_type: error.error_type,
                  platform: error.platform)

      get "/error_dashboard/errors/#{error.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("(Last 30 days)")
    end
  end

  # enable_breadcrumbs defaults to false, so the whole partial is gated off
  # unless the host app opts in.
  describe "breadcrumbs" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_breadcrumbs
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_breadcrumbs = was
    end

    before do
      error.update_column(:breadcrumbs, [ { "c" => "sql", "m" => "SELECT 1", "d" => 1 } ].to_json)
    end

    it "pluralizes the event count" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("1 event")
      expect(response.body).not_to include("1 events")
    end

    it "renders the trail's column labels" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Activity trail leading up to this error")
      expect(response.body).to include("Category")
    end
  end

  describe "co-occurring errors" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_co_occurring_errors
      RailsErrorDashboard.configuration.enable_co_occurring_errors = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_co_occurring_errors = was
    end

    # The correlation window feeds both the query and the hint beside it, so
    # the prose cannot drift from the data.
    #
    # Rendered directly rather than through a request: the card only appears
    # when the correlation query returns rows, and every id or title this page
    # carries also appears in the layout's section-navigation script, so a
    # "render it and check if the card showed up" guard silently passes whether
    # or not the card is there.
    it "renders the window from the same value the query uses" do
      allow(error).to receive(:co_occurring_errors).and_return([
        { error: create(:error_log, application: application, error_type: "ArgumentError"),
          frequency: 3, avg_delay_seconds: -12.0 }
      ])

      html = RailsErrorDashboard::ErrorsController.render(
        partial: "rails_error_dashboard/errors/co_occurring_errors",
        locals: { error: error }
      )

      expect(html).to include("within 5 minutes of this error")
      expect(html).to include("3 times")
    end
  end
end
