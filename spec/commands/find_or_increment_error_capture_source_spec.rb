# frozen_string_literal: true

require "rails_helper"

# backtrace_source describes the backtrace the error page shows, so it moves
# with that backtrace: when the grouping command replaces a one-line backtrace
# with a later capture's full one, and when a row is built by crash import or
# from a storm exemplar.
RSpec.describe "backtrace_source follows the shown backtrace" do
  let(:config) { RailsErrorDashboard.configuration }
  let(:application) { RailsErrorDashboard::Application.find_or_create_by_name("Capture Source App") }
  let(:error_hash) { "5011rce0f00d0001" }

  one_line = "app/models/order.rb:3:in 'total'"
  full = "app/models/order.rb:3:in 'total'\napp/controllers/orders_controller.rb:12:in 'create'"

  def capture(backtrace:, source:)
    RailsErrorDashboard::Commands::FindOrIncrementError.call(error_hash, {
      application_id: application.id,
      error_type: "NoMethodError",
      message: "undefined method 'total' for nil",
      backtrace: backtrace,
      occurred_at: Time.current,
      error_hash: error_hash,
      backtrace_source: source
    })
    RailsErrorDashboard::ErrorLog.find_by!(error_hash: error_hash)
  end

  describe "a later capture of the same error" do
    # capture-source/REQ-4
    it "makes the row server when a server capture replaces a client's one-line backtrace" do
      capture(backtrace: one_line, source: "client")

      expect(capture(backtrace: full, source: "server")).to have_attributes(backtrace: full, backtrace_source: "server")
    end

    # capture-source/REQ-4
    it "makes the row client when a client report replaces a one-line server backtrace" do
      capture(backtrace: one_line, source: "server")

      expect(capture(backtrace: full, source: "client")).to have_attributes(backtrace: full, backtrace_source: "client")
    end

    # capture-source/REQ-4
    it "leaves a full client backtrace, and its source, in place" do
      capture(backtrace: full, source: "client")

      expect(capture(backtrace: "#{full}\napp/jobs/x.rb:1", source: "server"))
        .to have_attributes(backtrace: full, backtrace_source: "client")
    end
  end

  describe "a row built from a storm exemplar" do
    let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }

    around do |example|
      saved = config.async_logging
      config.async_logging = false
      example.run
    ensure
      config.async_logging = saved
    end

    # A before hook, not the around above: rails_helper's global before turns
    # storm protection off and resets the gate, and runs after every around.
    # Every capture below is counted, not stored, until the flush.
    before do
      config.enable_storm_protection = true
      allow(gate.breaker).to receive(:record!).and_return(:open)
    end

    def flush
      RailsErrorDashboard::Commands::FlushStormCounts.call(entries: gate.count_buffer.snapshot![:entries])
    end

    # capture-source/REQ-2
    it "is server when the counted event was a server capture" do
      error = StandardError.new("storm exemplar from the server")
      error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:10:in 'explode'" ])

      RailsErrorDashboard::Commands::LogError.call(error, {})
      flush

      expect(RailsErrorDashboard::ErrorLog.find_by!(message: "storm exemplar from the server").backtrace_source).to eq("server")
    end

    # capture-source/REQ-4: the exemplar's frame is the one the client sent
    it "is client when the counted event was a client report" do
      RailsErrorDashboard::ManualErrorReporter.report(
        error_type: "TypeError",
        message: "storm exemplar from a client",
        backtrace: [ "app/models/widget.rb:10:in 'explode'" ]
      )
      flush

      expect(RailsErrorDashboard::ErrorLog.find_by!(message: "storm exemplar from a client").backtrace_source).to eq("client")
    end

    # capture-source/REQ-7: an entry buffered by a release without the field
    it "is server for an entry that carries no source" do
      error = StandardError.new("storm exemplar without a source")
      error.set_backtrace([ "#{Rails.root}/app/models/widget.rb:11:in 'explode'" ])
      RailsErrorDashboard::Commands::LogError.call(error, {})
      entries = gate.count_buffer.snapshot![:entries].map { |entry| entry.except("capture_source") }

      RailsErrorDashboard::Commands::FlushStormCounts.call(entries: entries)

      expect(RailsErrorDashboard::ErrorLog.find_by!(message: "storm exemplar without a source").backtrace_source).to eq("server")
    end
  end

  # capture-source/REQ-2
  it "is server for an imported crash" do
    dir = Dir.mktmpdir("red_crash_source")
    saved = [ config.enable_crash_capture, config.crash_capture_path ]
    config.enable_crash_capture = true
    config.crash_capture_path = dir
    File.write(File.join(dir, "red_crash_4242.json"), JSON.generate(
      exception_class: "RuntimeError", message: "crash source probe", backtrace: [ "app/models/user.rb:42:in 'save!'" ],
      timestamp: Time.now.utc.iso8601, pid: 4242, ruby_version: RUBY_VERSION, cause_chain: []
    ))

    RailsErrorDashboard::Services::CrashCapture.import!

    expect(RailsErrorDashboard::ErrorLog.find_by!(message: "crash source probe").backtrace_source).to eq("server")
  ensure
    config.enable_crash_capture, config.crash_capture_path = saved
    FileUtils.rm_rf(dir)
  end
end
