# frozen_string_literal: true

require "rails_helper"

# The error row holds its latest capture's context; ?occurrence=ID shows the
# context stored for one earlier occurrence in the same cards.
RSpec.describe "Error page for one occurrence", type: :request do
  let(:config) { RailsErrorDashboard.configuration }
  let(:error) { create(:error_log, **context_values("latest")) }

  around do |example|
    flags = %i[enable_breadcrumbs enable_system_health enable_local_variables enable_instance_variables]
    saved = flags.map { |flag| config.public_send(flag) }
    flags.each { |flag| config.public_send("#{flag}=", true) }
    config.authenticate_with = -> { true }
    example.run
  ensure
    flags.zip(saved).each { |flag, value| config.public_send("#{flag}=", value) }
    config.authenticate_with = nil
  end

  # The four pieces, each carrying `marker` where the page shows it
  def context_values(marker)
    {
      breadcrumbs: [ { "t" => 1_700_000_000_000, "c" => "custom", "m" => "crumb-#{marker}" } ].to_json,
      system_health: { process_memory: { rss_mb: marker == "latest" ? 111.5 : 222.5 } }.to_json,
      local_variables: { "local_#{marker}" => { "type" => "String", "value" => "lv" } }.to_json,
      instance_variables: { "@ivar_#{marker}" => { "type" => "String", "value" => "iv" } }.to_json
    }
  end

  def stored_context(for_error, marker, occurred_at: 2.hours.ago)
    occurrence = create(:error_occurrence, error_log: for_error, occurred_at: occurred_at)
    RailsErrorDashboard::ErrorOccurrenceContext.create!(
      context_values(marker).merge(error_occurrence: occurrence, error_log: for_error, created_at: occurred_at)
    )
    occurrence
  end

  # What the page displays: the cards' text, not attributes such as the Copy
  # for LLM button's markdown, which stays the error row's (the banner says so)
  def page_text
    Nokogiri::HTML(response.body).tap { |doc| doc.css("script").remove }.text
  end

  def expect_latest_snapshot
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("crumb-latest", "local_latest", "@ivar_latest", "111.5 MB")
    expect(response.body).not_to include("occurrence-banner")
  end

  # occurrence-context-history/REQ-6
  it "shows the breadcrumb, system-health and variable cards from that occurrence's context" do
    occurrence = stored_context(error, "older")

    get "/error_dashboard/errors/#{error.id}", params: { occurrence: occurrence.id }

    expect(response).to have_http_status(:ok)
    expect(page_text).to include("crumb-older", "local_older", "@ivar_older", "222.5 MB")
    expect(page_text).not_to include("crumb-latest", "local_latest", "@ivar_latest", "111.5 MB")
  end

  # occurrence-context-history/REQ-6
  it "says which occurrence, and when, it is showing, with a link back to the latest" do
    occurrence = stored_context(error, "older", occurred_at: Time.utc(2026, 10, 1, 12, 0))

    get "/error_dashboard/errors/#{error.id}", params: { occurrence: occurrence.id }

    banner = Nokogiri::HTML(response.body).at_css("#occurrence-banner")
    expect(banner).to be_present
    expect(banner.text).to include("##{occurrence.id}")
    expect(banner.at_css(".local-time")["data-utc"]).to eq("2026-10-01T12:00:00Z")
    expect(banner.at_css("a[href='/error_dashboard/errors/#{error.id}']")).to be_present
  end

  # occurrence-context-history/REQ-6: a piece the occurrence did not capture is
  # not filled in from the latest capture
  it "leaves out a card the occurrence has no value for" do
    occurrence = stored_context(error, "older")
    RailsErrorDashboard::ErrorOccurrenceContext.where(error_occurrence_id: occurrence.id).update_all(breadcrumbs: nil)

    get "/error_dashboard/errors/#{error.id}", params: { occurrence: occurrence.id }

    expect(page_text).to include("local_older")
    expect(page_text).not_to include("crumb-latest", "crumb-older")
  end

  # occurrence-context-history/REQ-7
  it "shows the latest snapshot without an occurrence" do
    stored_context(error, "older")

    get "/error_dashboard/errors/#{error.id}"

    expect_latest_snapshot
  end

  # occurrence-context-history/REQ-7
  it "shows the latest snapshot for an occurrence with no stored context" do
    bare = create(:error_occurrence, error_log: error)

    get "/error_dashboard/errors/#{error.id}", params: { occurrence: bare.id }

    expect_latest_snapshot
  end

  # occurrence-context-history/REQ-9
  it "never shows another error's context for its occurrence id" do
    other = create(:error_log)
    foreign = stored_context(other, "foreign")

    get "/error_dashboard/errors/#{error.id}", params: { occurrence: foreign.id }

    expect_latest_snapshot
    expect(response.body).not_to include("crumb-foreign", "local_foreign", "@ivar_foreign", "222.5 MB")
  end

  # occurrence-context-history/REQ-9
  it "shows the latest snapshot for an occurrence id that does not exist" do
    get "/error_dashboard/errors/#{error.id}", params: { occurrence: 0 }

    expect_latest_snapshot
  end

  # The copy that carries the occurrence's values is read-only: the page can
  # never write them over the error row
  it "leaves the error row's snapshot untouched" do
    occurrence = stored_context(error, "older")

    get "/error_dashboard/errors/#{error.id}", params: { occurrence: occurrence.id }

    expect(error.reload.breadcrumbs).to include("crumb-latest")
  end
end
