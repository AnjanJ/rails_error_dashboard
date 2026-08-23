# frozen_string_literal: true

require "rails_helper"

# The detail page's metadata sidebar. It is the densest single view in the
# dashboard, and most of its content is telemetry — so these specs pin the line
# between UI text (translated) and diagnostic output (left English), plus the
# escaping the extraction could have quietly broken.
RSpec.describe "Sidebar metadata translations", type: :request do
  let!(:application) { create(:application) }
  let!(:error) do
    create(:error_log, application: application, error_type: "SecurityError",
           occurrence_count: 4)
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "metadata fields" do
    it "renders the section labels" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Occurrence Count")
      expect(response.body).to include("First Seen")
      expect(response.body).to include("Severity Level")
      expect(response.body).to include("Error ID")
    end

    it "pluralizes the occurrence sentence" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("This error has occurred 4 times")
    end

    it "omits the occurrence sentence for a single occurrence" do
      single = create(:error_log, application: application, occurrence_count: 1)

      get "/error_dashboard/errors/#{single.id}"

      expect(response.body).not_to include("This error has occurred 1 time")
    end

    it "renders the guest label when there is no user" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Guest / Unauthenticated")
    end
  end

  describe "severity badge" do
    # The badge text was four hardcoded uppercase literals; it is now a key
    # lookup, and the badge class stays keyed on the machine value.
    it "renders the uppercased label with the matching badge class" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("CRITICAL")
      expect(response.body).to match(/badge bg-danger fs-6[^>]*>\s*CRITICAL/)
    end

    it "titles the severity link with the translated label" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("View all Critical errors")
    end
  end

  describe "issue tracking notice" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_issue_tracking
      RailsErrorDashboard.configuration.enable_issue_tracking = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_issue_tracking = was
    end

    it "renders the unlinked sentence when no issue is linked" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Link an issue to see details.")
    end

    # The linked variant interpolates an <a> into an _html key, which is
    # html_safe. Building the tag with link_to rather than putting the href in
    # the key is what keeps a hostile URL from breaking out of the attribute.
    it "escapes a hostile external issue url instead of injecting an attribute" do
      error.update_column(:external_issue_url, %q{" onmouseover="alert(1)})

      get "/error_dashboard/errors/#{error.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("linked issue")
      expect(response.body).not_to include(%q{onmouseover="alert(1)"})
      expect(response.body).to include("&quot; onmouseover=&quot;alert(1)")
    end

    it "renders a normal issue url as a working link" do
      error.update_column(:external_issue_url, "https://github.com/o/r/issues/1")

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include('href="https://github.com/o/r/issues/1"')
      expect(response.body).to include("linked issue")
    end
  end

  describe "environment section" do
    it "renders the field labels" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Environment")
      expect(response.body).to include("Rails:")
      expect(response.body).to include("Ruby:")
    end

    # A Rails environment name is whatever the host app calls it. titleize
    # applied English morphology to that identifier.
    it "shows the environment name verbatim rather than titleized" do
      error.update_column(:environment_info, { rails_env: "staging_eu" }.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("staging_eu")
      expect(response.body).not_to include("Staging Eu")
    end
  end

  describe "system health section" do
    around do |example|
      was = RailsErrorDashboard.configuration.enable_system_health
      RailsErrorDashboard.configuration.enable_system_health = true
      example.run
    ensure
      RailsErrorDashboard.configuration.enable_system_health = was
    end

    let(:health) do
      {
        process_memory: { rss_mb: 256.0, os_threads: 12 },
        thread_count: 8,
        tcp_connections: { established: 5, close_wait: 2 },
        job_queue: { adapter: "sidekiq", enqueued: 3, workers: 2 }
      }
    end

    it "translates the metric labels" do
      error.update_column(:system_health, health.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Memory (RSS):")
      expect(response.body).to include("TCP Connections:")
      expect(response.body).to include("OS Threads:")
    end

    # Per the glossary: the values are diagnostic output developers search for,
    # so they stay English even in a translated dashboard.
    it "leaves the machine-state tokens in the values untranslated" do
      error.update_column(:system_health, health.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("close_wait")
      expect(response.body).to include("established")
      expect(response.body).to include("enqueued")
    end

    it "interpolates the ruby thread count rather than concatenating it" do
      error.update_column(:system_health, health.to_json)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("(Ruby: 8)")
    end
  end
end
