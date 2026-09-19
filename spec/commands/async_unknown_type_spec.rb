# frozen_string_literal: true

require "rails_helper"

# A frontend or mobile client reports an error type that does not exist as a
# Ruby class in the server -- that is the normal shape of ManualErrorReporter,
# not an edge case. The async path reconstructed an exception object from the
# payload to read its class name back off it, so an unconstantizable type was
# silently renamed StandardError and every distinct frontend error collapsed
# into one indistinguishable group.
RSpec.describe "async capture of an unknown error type" do
  let(:logs) { RailsErrorDashboard::ErrorLog }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.async_logging = true
    config.enable_storm_protection = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "preserves the reported type through the queue" do
    RailsErrorDashboard::ManualErrorReporter.report(
      error_type: "FrontendWidgetFailure",
      message: "widget exploded",
      platform: "Web"
    )
    perform_enqueued_jobs

    expect(logs.sole.error_type).to eq("FrontendWidgetFailure")
  end

  it "keeps two different unknown types in separate groups" do
    RailsErrorDashboard::ManualErrorReporter.report(error_type: "FrontendWidgetFailure", message: "a")
    RailsErrorDashboard::ManualErrorReporter.report(error_type: "FrontendRouterFailure", message: "b")
    perform_enqueued_jobs

    expect(logs.pluck(:error_type)).to match_array(%w[FrontendWidgetFailure FrontendRouterFailure])
  end

  it "still resolves a real Ruby class normally" do
    RailsErrorDashboard::Commands::LogError.call(ArgumentError.new("real class"))
    perform_enqueued_jobs

    expect(logs.sole.error_type).to eq("ArgumentError")
  end
end
