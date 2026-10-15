# frozen_string_literal: true

require "rails_helper"

# The error-info fragment held the source viewer, blame, repository links and
# the coverage overlay, keyed only on the error row and the locale: turning
# source integration on or off, changing the repository URL, or a deploy that
# changed the file did nothing to the page until the error itself changed.
RSpec.describe "Error info fragment cache", type: :request do
  let(:error) { create(:error_log) }

  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }

  around do |example|
    store = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    Rails.cache.clear
    example.run
  ensure
    ActionController::Base.perform_caching = store
    Rails.cache.clear
    RailsErrorDashboard.reset_configuration!
  end

  # Every fragment write for the error-info partial: [key, options].
  def record_fragment_writes
    writes = []
    allow(Rails.cache).to receive(:write).and_wrap_original do |original, key, *args|
      writes << [ key, args.last.is_a?(Hash) ? args.last : {} ] if Array(key).flatten.include?("error_details_v3")
      original.call(key, *args)
    end
    writes
  end

  it "keys the fragment on the source-integration configuration" do
    writes = record_fragment_writes

    get "/error_dashboard/errors/#{error.id}"
    config = RailsErrorDashboard.configuration
    config.enable_source_code_integration = !config.enable_source_code_integration
    get "/error_dashboard/errors/#{error.id}"

    expect(writes.size).to eq(2)
    expect(writes[0][0]).not_to eq(writes[1][0])
  end

  it "does not cache the fragment while coverage tracking is live" do
    allow(RailsErrorDashboard::Services::CoverageTracker).to receive(:active?).and_return(true)
    writes = record_fragment_writes

    get "/error_dashboard/errors/#{error.id}"

    expect(response).to have_http_status(:ok)
    expect(writes).to be_empty
  end

  it "gives the fragment the source cache TTL when source integration is on" do
    RailsErrorDashboard.configuration.enable_source_code_integration = true
    RailsErrorDashboard.configuration.source_code_cache_ttl = 60
    writes = record_fragment_writes

    get "/error_dashboard/errors/#{error.id}"

    expect(writes.size).to eq(1)
    expect(writes[0][1]).to include(expires_in: 60.seconds)
  end
end
