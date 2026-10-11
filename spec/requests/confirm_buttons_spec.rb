# frozen_string_literal: true

require "rails_helper"

# The dashboard runs with Turbo off and loads no rails-ujs, so data-confirm
# and data-turbo-confirm were attributes nobody read: Batch Delete deleted on
# the first click. The layout's own confirm-submit handler is the one reader.
RSpec.describe "Destructive buttons confirm", type: :request do
  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }
  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  def doc
    Nokogiri::HTML(response.body)
  end

  it "asks before a batch delete, through the handler the layout actually has" do
    create(:error_log)
    get "/error_dashboard/errors"

    button = doc.at_css('#batch-form button[value="delete"]')
    expect(button["data-red-action"]).to eq("confirm-submit")
    expect(button["data-red-confirm-message"]).to include("delete the selected errors")
    expect(response.body).not_to include('data-confirm="')
    expect(response.body).to include("case 'confirm-submit'")
  end

  it "asks before removing an assignment" do
    error = create(:error_log, assigned_to: "gandalf", assigned_at: Time.current)
    get "/error_dashboard/errors/#{error.id}"

    form = doc.css("form").find { |f| f["action"]&.end_with?("/unassign") }
    expect(form).to be_present
    expect(form["data-red-action"]).to eq("confirm-submit")
    expect(form["data-red-confirm-message"]).to be_present
    expect(response.body).not_to include("data-turbo-confirm")
  end
end
