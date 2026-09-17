# frozen_string_literal: true

require "rails_helper"

# The search box in the top bar was an <input> with no form and no name: the
# "/" shortcut focused it, and pressing Enter did nothing. It is a GET form to
# the errors index, the same parameter the index's own search field uses.
RSpec.describe "Global search box", type: :request do
  let!(:application) { create(:application) }

  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }
  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  def search_form(body)
    Nokogiri::HTML(body).at_css("form:has(input#globalSearch)")
  end

  it "is a GET form to the errors index with a named search field" do
    get "/error_dashboard/errors/analytics"

    form = search_form(response.body)
    expect(form).to be_present
    expect(form["action"]).to eq("/error_dashboard/errors")
    expect(form["method"].to_s.downcase).to eq("get")
    expect(form.at_css("input#globalSearch")["name"]).to eq("search")
  end

  it "adds no CSRF token or utf8 field to the query string" do
    get "/error_dashboard/errors"

    names = search_form(response.body).css("input").map { |i| i["name"] }
    expect(names).to eq([ "search" ])
  end

  it "carries the application in context as a hidden field" do
    get "/error_dashboard/errors", params: { application_id: application.id }

    hidden = search_form(response.body).at_css("input[type=hidden][name=application_id]")
    expect(hidden).to be_present
    expect(hidden["value"]).to eq(application.id.to_s)
  end

  it "pre-fills the box with the current search" do
    get "/error_dashboard/errors", params: { search: "NoMethodError" }

    expect(search_form(response.body).at_css("input#globalSearch")["value"]).to eq("NoMethodError")
  end

  it "escapes a hostile search term in the pre-filled value" do
    hostile = %("><script>window.__X=1</script>)

    get "/error_dashboard/errors", params: { search: hostile }

    expect(response.body).not_to include("<script>window.__X=1</script>")
    expect(search_form(response.body).at_css("input#globalSearch")["value"]).to eq(hostile)
  end

  it "ignores search and application_id sent as nested parameters" do
    get "/error_dashboard/errors/analytics", params: { search: { "a" => "b" }, application_id: { "x" => "1" } }

    expect(response).to have_http_status(:ok)
    form = search_form(response.body)
    expect(form.at_css("input#globalSearch")["value"].to_s).to eq("")
    expect(form.at_css("input[name=application_id]")).to be_nil
  end

  it "finds errors when submitted" do
    hit = create(:error_log, application: application, message: "needle in the haystack")
    miss = create(:error_log, application: application, message: "nothing to see")

    get "/error_dashboard/errors", params: { search: "needle" }

    expect(response.body).to include(hit.message)
    expect(response.body).not_to include(miss.message)
  end
end
