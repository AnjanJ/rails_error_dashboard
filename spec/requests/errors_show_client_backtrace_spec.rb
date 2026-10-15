# frozen_string_literal: true

require "rails_helper"

# A backtrace a client sent through ManualErrorReporter describes code that ran
# on the client, so the error page reads no source file and runs no blame for
# it, and says why.
RSpec.describe "Error page for a client-reported backtrace", type: :request do
  let(:config) { RailsErrorDashboard.configuration }
  let(:frames) { "app/models/order.rb:3:in 'total'\napp/controllers/orders_controller.rb:12:in 'create'" }
  let(:note) { "came from a client report" }

  around do |example|
    saved = [ config.enable_source_code_integration, config.enable_git_blame ]
    config.enable_source_code_integration = true
    config.enable_git_blame = true
    config.authenticate_with = -> { true }
    example.run
  ensure
    config.enable_source_code_integration, config.enable_git_blame = saved
    config.authenticate_with = nil
  end

  before do
    allow(RailsErrorDashboard::Services::SourceCodeReader).to receive(:new).and_call_original
    allow(RailsErrorDashboard::Services::GitBlameReader).to receive(:new).and_call_original
  end

  def view_source_toggles
    Nokogiri::HTML(response.body).css("[data-bs-target^='#source-code-']")
  end

  # capture-source/REQ-4, capture-source/REQ-5, capture-source/REQ-6: no reader
  # is built for the whole request, Copy for LLM's text included (the formatter
  # spec proves the snippet itself with a real file)
  it "offers no View Source, reads no file, runs no blame, and says why" do
    error = create(:error_log, backtrace: frames, backtrace_source: "client")

    get "/error_dashboard/errors/#{error.id}"

    expect(response).to have_http_status(:ok)
    expect(view_source_toggles).to be_empty
    expect(RailsErrorDashboard::Services::SourceCodeReader).not_to have_received(:new)
    expect(RailsErrorDashboard::Services::GitBlameReader).not_to have_received(:new)
    expect(response.body).to include(note)
  end

  # capture-source/REQ-4: the same frames captured on the server still get it
  it "still offers View Source for a server capture" do
    error = create(:error_log, backtrace: frames, backtrace_source: "server")

    get "/error_dashboard/errors/#{error.id}"

    expect(view_source_toggles).not_to be_empty
    expect(RailsErrorDashboard::Services::SourceCodeReader).to have_received(:new).at_least(:once)
    expect(response.body).not_to include(note)
  end

  # capture-source/REQ-7
  it "treats an error recorded before capture sources as server" do
    error = create(:error_log, backtrace: frames, backtrace_source: nil)

    get "/error_dashboard/errors/#{error.id}"

    expect(view_source_toggles).not_to be_empty
    expect(response.body).not_to include(note)
  end
end
