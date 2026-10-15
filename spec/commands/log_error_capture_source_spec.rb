# frozen_string_literal: true

require "rails_helper"

# Every capture records where it came from: "client" for a ManualErrorReporter
# report, "server" for RED's own captures. The error row's backtrace_source
# says the same for the backtrace it shows.
RSpec.describe "LogError records the capture source" do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = config.async_logging
    config.async_logging = false
    example.run
  ensure
    config.async_logging = saved
  end

  def report_from_client(**extra)
    RailsErrorDashboard::ManualErrorReporter.report(
      error_type: "TypeError",
      message: "client says undefined is not a function",
      backtrace: [ "app/controllers/orders_controller.rb:12:in 'create'", "app/models/order.rb:3:in 'total'" ],
      platform: "Web",
      **extra
    )
  end

  def client_error
    RailsErrorDashboard::ErrorLog.find_by!(message: "client says undefined is not a function")
  end

  # The same line every time, so every call is one error group
  def server_exception
    raise ArgumentError, "server side capture source probe"
  rescue ArgumentError => e
    e
  end

  def server_error
    RailsErrorDashboard::ErrorLog.find_by!(message: "server side capture source probe")
  end

  def sources(error)
    [ error.backtrace_source, error.error_occurrences.order(:id).pluck(:capture_source) ]
  end

  describe "a ManualErrorReporter report" do
    # capture-source/REQ-1
    it "is client, when logged synchronously" do
      report_from_client

      expect(sources(client_error)).to eq([ "client", [ "client" ] ])
    end

    # capture-source/REQ-1
    it "is client, when logged by the async job" do
      config.async_logging = true

      report_from_client
      perform_enqueued_jobs

      expect(sources(client_error)).to eq([ "client", [ "client" ] ])
    end

    # capture-source/REQ-1: the caller's own fields never decide it
    it "is client whatever the caller passes as its source or metadata" do
      report_from_client(source: "server", metadata: { _capture_source: "server", capture_source: "server" })

      expect(sources(client_error)).to eq([ "client", [ "client" ] ])
    end
  end

  describe "RED's own captures" do
    # capture-source/REQ-2
    it "are server through the middleware" do
      app = ->(_env) { raise server_exception }
      env = Rack::MockRequest.env_for("/orders")

      expect { RailsErrorDashboard::Middleware::ErrorCatcher.new(app).call(env) }.to raise_error(ArgumentError)

      expect(sources(server_error)).to eq([ "server", [ "server" ] ])
    end

    # capture-source/REQ-2
    it "are server through the Rails.error subscriber" do
      # Not :warning, the default for a handled report, which the subscriber skips
      Rails.error.report(server_exception, handled: true, severity: :error)

      expect(sources(server_error)).to eq([ "server", [ "server" ] ])
    end

    # capture-source/REQ-2
    it "are server through ErrorLog.log_error" do
      RailsErrorDashboard::ErrorLog.log_error(server_exception, {})

      expect(sources(server_error)).to eq([ "server", [ "server" ] ])
    end

    # capture-source/REQ-2
    it "are server through the async job" do
      config.async_logging = true

      RailsErrorDashboard::Commands::LogError.call(server_exception, {})
      perform_enqueued_jobs

      expect(sources(server_error)).to eq([ "server", [ "server" ] ])
    end

    # capture-source/REQ-2: only the exact marker ManualErrorReporter sets counts
    it "are server when the context has no marker, or not the client one" do
      RailsErrorDashboard::Commands::LogError.call(server_exception, { _capture_source: nil })
      RailsErrorDashboard::Commands::LogError.call(server_exception, { _capture_source: "Client" })

      expect(sources(server_error)).to eq([ "server", [ "server", "server" ] ])
    end
  end

  # capture-source/REQ-3
  it "groups a client report and a server capture of the same error together" do
    exception = server_exception

    RailsErrorDashboard::Commands::LogError.call(exception, {})
    RailsErrorDashboard::Commands::LogError.call(exception, { _capture_source: "client" })

    expect(RailsErrorDashboard::ErrorLog.where(message: "server side capture source probe").count).to eq(1)
    expect(sources(server_error)).to eq([ "server", [ "server", "client" ] ])
  end

  # capture-source/REQ-8
  it "still records the error when the occurrence carrying the marker cannot be written" do
    allow(RailsErrorDashboard::ErrorOccurrence).to receive(:create).and_raise(ActiveRecord::StatementInvalid, "disk full")

    expect { report_from_client }.not_to raise_error

    expect(client_error.backtrace_source).to eq("client")
    expect(client_error.error_occurrences).to be_empty
  end
end
