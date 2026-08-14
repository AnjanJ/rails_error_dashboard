# frozen_string_literal: true

require "rails_helper"

# The error detail page. These specs pin what extraction could quietly break
# here: the fragment cache must not serve one locale's text to another, the
# hero's interpolated markup must survive, and the status badge must stay in
# agreement with the index's copy of the same labels.
RSpec.describe "Error show translations", type: :request do
  let!(:application) { create(:application) }
  let!(:error) do
    create(:error_log, application: application, error_type: "SecurityError",
           message: "something exploded", occurrence_count: 3)
  end

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
  end

  describe "hero" do
    it "renders the breadcrumb and action buttons" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Errors")
      expect(response.body).to include("Assign")
      expect(response.body).to include("Copy for LLM")
    end

    it "interpolates the styled occurrence count without escaping its markup" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to match(%r{<strong style="color: var\(--text-primary\);">3</strong> occurrences})
      expect(response.body).not_to include("&lt;strong")
    end

    it "uses the singular form for a single occurrence" do
      single = create(:error_log, application: application, occurrence_count: 1)

      get "/error_dashboard/errors/#{single.id}"

      expect(response.body).to match(%r{</strong> occurrence\b})
    end

    it "keeps the relative-time markup intact in first/last seen" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to match(/First seen\s*<span/)
      expect(response.body).not_to include("First seen &lt;span")
    end
  end

  describe "status badge" do
    # The show page and the index row render the same workflow status. Both
    # read red.errors.row.status.*; if one is edited to a literal this catches
    # the drift.
    it "translates the status while keeping the colour keyed on the raw value" do
      error.update!(status: "in_progress", resolved: false)

      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("in progress")
      expect(response.body).to include("var(--status-info)")
    end

    it "renders a translated severity label rather than the raw symbol" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Critical")
    end
  end

  describe "error info partial" do
    it "renders the message and backtrace labels" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to include("Error Message:")
      expect(response.body).to include("Backtrace:")
    end

    it "pluralizes the frame count" do
      get "/error_dashboard/errors/#{error.id}"

      expect(response.body).to match(/\d+ frames?</)
    end

    it "renders the empty state when there is no backtrace" do
      bare = create(:error_log, application: application, backtrace: nil)

      get "/error_dashboard/errors/#{bare.id}"

      expect(response.body).to include("No backtrace available")
    end
  end

  # The partial is fragment-cached. Before the locale joined the cache key, the
  # first locale to render an error was served to every other one.
  describe "fragment cache" do
    around do |example|
      store = ActionController::Base.perform_caching
      ActionController::Base.perform_caching = true
      Rails.cache.clear
      example.run
    ensure
      ActionController::Base.perform_caching = store
      Rails.cache.clear
    end

    # Only en ships today, so there is no second locale to render and compare
    # against until P6-T2. What can be asserted now is the property that makes
    # such a comparison safe later: the locale is part of the key the fragment
    # is written under.
    it "includes the locale in the fragment cache key" do
      written_keys = []
      allow(Rails.cache).to receive(:write).and_wrap_original do |original, key, *args|
        written_keys << key
        original.call(key, *args)
      end

      get "/error_dashboard/errors/#{error.id}"

      # Assert on the key's structure, not on a substring of its inspected
      # form: the serialized ErrorLog carries a user_agent that can contain
      # almost any text, so a substring match for "en" passes by accident.
      info_key = written_keys.find do |key|
        Array(key).flatten.any? { |part| part == "error_details_v2" }
      end
      expect(info_key).to be_present, "expected the error_info fragment to be cached"

      parts = Array(info_key).flatten
      expect(parts.last).to eq("en")
    end

    it "serves the cached fragment on a second request" do
      get "/error_dashboard/errors/#{error.id}"
      first_body = response.body

      get "/error_dashboard/errors/#{error.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Error Message:")
      expect(response.body.include?("Backtrace:")).to eq(first_body.include?("Backtrace:"))
    end
  end
end
