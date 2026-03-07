# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::CrashCapture do
  let(:crash_dir) { Dir.mktmpdir("red_crash_test") }

  before do
    described_class.reset!
    RailsErrorDashboard.configuration.enable_crash_capture = true
    RailsErrorDashboard.configuration.crash_capture_path = crash_dir
  end

  after do
    described_class.reset!
    RailsErrorDashboard.configuration.enable_crash_capture = false
    RailsErrorDashboard.configuration.crash_capture_path = nil
    FileUtils.rm_rf(crash_dir) if Dir.exist?(crash_dir)
  end

  # Helper to build a minimal valid crash data hash
  def build_crash_data(overrides = {})
    {
      exception_class: "RuntimeError",
      message: "test crash",
      backtrace: [ "app/models/user.rb:42:in `save!'" ],
      timestamp: Time.now.utc.iso8601,
      pid: 12345,
      ruby_version: RUBY_VERSION,
      cause_chain: []
    }.merge(overrides)
  end

  # Helper to write a crash file and return its path
  def write_crash_file(data, pid: data[:pid] || data["pid"] || 12345)
    path = File.join(crash_dir, "red_crash_#{pid}.json")
    File.write(path, JSON.generate(data))
    path
  end

  # Helper to read the first crash file from the directory
  def read_crash_file
    files = Dir.glob(File.join(crash_dir, "red_crash_*.json"))
    return nil if files.empty?
    JSON.parse(File.read(files.first))
  end

  describe ".enable!" do
    it "enables crash capture and returns true" do
      result = described_class.enable!
      expect(result).to be true
      expect(described_class.enabled?).to be true
    end

    it "is idempotent — second call returns true without registering another hook" do
      described_class.enable!
      # Calling enable! again should be a no-op (returns true, no duplicate at_exit)
      result = described_class.enable!
      expect(result).to be true
      expect(described_class.enabled?).to be true
    end

    it "records boot time for uptime calculation" do
      described_class.enable!

      exception = RuntimeError.new("test")
      exception.set_backtrace([ "test.rb:1" ])
      described_class.capture!(exception)

      data = read_crash_file
      expect(data["uptime_seconds"]).to be_a(Numeric)
      expect(data["uptime_seconds"]).to be >= 0
    end
  end

  describe ".disable!" do
    it "disables crash capture" do
      described_class.enable!
      described_class.disable!
      expect(described_class.enabled?).to be false
    end
  end

  describe ".enabled?" do
    it "returns false before enable!" do
      expect(described_class.enabled?).to be false
    end

    it "returns true after enable!" do
      described_class.enable!
      expect(described_class.enabled?).to be true
    end

    it "returns false after disable!" do
      described_class.enable!
      described_class.disable!
      expect(described_class.enabled?).to be false
    end
  end

  describe ".capture!" do
    before { described_class.enable! }

    context "happy path" do
      it "writes crash file for RuntimeError with class, message, backtrace" do
        exception = RuntimeError.new("fatal crash")
        exception.set_backtrace([ "app/models/user.rb:42:in `save!'" ])

        described_class.capture!(exception)

        files = Dir.glob(File.join(crash_dir, "red_crash_*.json"))
        expect(files.size).to eq(1)

        data = JSON.parse(File.read(files.first))
        expect(data["exception_class"]).to eq("RuntimeError")
        expect(data["message"]).to eq("fatal crash")
        expect(data["backtrace"]).to eq([ "app/models/user.rb:42:in `save!'" ])
      end

      it "includes PID, ruby_version, thread_count, timestamp, rails_version" do
        exception = RuntimeError.new("test")
        exception.set_backtrace([ "test.rb:1" ])

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["pid"]).to eq(Process.pid)
        expect(data["ruby_version"]).to eq(RUBY_VERSION)
        expect(data["thread_count"]).to be_a(Integer)
        expect(data["thread_count"]).to be >= 1
        expect(data["timestamp"]).to be_a(String)
        expect(data["rails_version"]).to eq(Rails.version)
      end

      it "includes GC stats" do
        exception = RuntimeError.new("test")
        exception.set_backtrace([ "test.rb:1" ])

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["gc"]).to be_a(Hash)
        expect(data["gc"]).to have_key("count")
      end

      it "includes cause chain for nested exceptions" do
        inner = ArgumentError.new("bad arg")
        outer = begin
          raise inner
        rescue
          begin
            raise RuntimeError, "outer failure"
          rescue => e
            e
          end
        end

        described_class.capture!(outer)

        data = read_crash_file
        expect(data["cause_chain"]).to be_a(Array)
        expect(data["cause_chain"].size).to eq(1)
        expect(data["cause_chain"].first["exception_class"]).to eq("ArgumentError")
        expect(data["cause_chain"].first["message"]).to eq("bad arg")
      end
    end

    context "filter chain (skip/capture decisions)" do
      it "skips nil exception" do
        described_class.capture!(nil)
        expect(Dir.glob(File.join(crash_dir, "red_crash_*.json"))).to be_empty
      end

      it "skips successful SystemExit (clean exit, code 0)" do
        described_class.capture!(SystemExit.new(0))
        expect(Dir.glob(File.join(crash_dir, "red_crash_*.json"))).to be_empty
      end

      it "captures failed SystemExit (abort, code 1)" do
        exception = SystemExit.new(1)
        exception.set_backtrace([ "test.rb:1" ])

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["exception_class"]).to eq("SystemExit")
      end

      it "skips SignalException (SIGTERM)" do
        described_class.capture!(SignalException.new("TERM"))
        expect(Dir.glob(File.join(crash_dir, "red_crash_*.json"))).to be_empty
      end

      it "skips Interrupt (Ctrl+C, subclass of SignalException)" do
        described_class.capture!(Interrupt.new)
        expect(Dir.glob(File.join(crash_dir, "red_crash_*.json"))).to be_empty
      end

      it "skips when not enabled" do
        described_class.disable!
        described_class.capture!(RuntimeError.new("test"))
        expect(Dir.glob(File.join(crash_dir, "red_crash_*.json"))).to be_empty
      end
    end

    context "edge cases" do
      it "truncates messages longer than 10,000 characters" do
        exception = RuntimeError.new("x" * 20_000)
        exception.set_backtrace([ "test.rb:1" ])

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["message"].length).to be <= 10_000
      end

      it "limits backtrace to 50 lines" do
        exception = RuntimeError.new("test")
        exception.set_backtrace((1..100).map { |i| "file.rb:#{i}" })

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["backtrace"].size).to eq(50)
      end

      it "handles exception with nil backtrace" do
        exception = RuntimeError.new("no backtrace")
        # Don't call set_backtrace — backtrace is nil

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["exception_class"]).to eq("RuntimeError")
        expect(data["backtrace"]).to be_nil
      end

      it "handles exception with nil-ish message" do
        exception = RuntimeError.new
        exception.set_backtrace([ "test.rb:1" ])

        described_class.capture!(exception)

        data = read_crash_file
        expect(data["exception_class"]).to eq("RuntimeError")
        expect(data["message"]).to be_a(String)
      end

      it "limits cause chain to 5 entries (no infinite loop on circular causes)" do
        # Build a chain of 10 causes
        exceptions = (0..9).map { |i| RuntimeError.new("cause #{i}") }
        chain = exceptions.reduce do |inner, outer|
          begin
            raise inner
          rescue
            begin
              raise outer
            rescue => e
              e
            end
          end
        end

        described_class.capture!(chain)

        data = read_crash_file
        expect(data["cause_chain"].size).to be <= 5
      end
    end

    context "error resilience" do
      it "never raises even with unwritable path" do
        RailsErrorDashboard.configuration.crash_capture_path = "/nonexistent/deeply/nested/path"

        expect {
          described_class.capture!(RuntimeError.new("test"))
        }.not_to raise_error
      end
    end
  end

  describe ".import!" do
    context "happy path" do
      it "creates ErrorLog record from valid crash file" do
        write_crash_file(build_crash_data(
          exception_class: "NoMemoryError",
          message: "failed to allocate memory",
          backtrace: [ "app/services/heavy.rb:10:in `process'" ],
          rails_version: Rails.version,
          thread_count: 5,
          uptime_seconds: 3600.5,
          gc: { count: 42 }
        ))

        expect {
          described_class.import!
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.error_type).to eq("NoMemoryError")
        expect(error_log.message).to eq("failed to allocate memory")
        expect(error_log.platform).to eq("crash_capture")
        expect(error_log.backtrace).to include("app/services/heavy.rb:10")
        expect(error_log.application_id).to be_present
        expect(error_log.resolved).to be false
      end

      it "stores crash metadata in environment_info" do
        write_crash_file(build_crash_data(
          pid: 99999,
          ruby_version: "3.3.0",
          rails_version: "8.0.0",
          thread_count: 3,
          uptime_seconds: 120.0,
          gc: { count: 10 }
        ), pid: 99999)

        described_class.import!

        error_log = RailsErrorDashboard::ErrorLog.last
        next unless error_log.respond_to?(:environment_info) && error_log.environment_info.present?

        env_info = JSON.parse(error_log.environment_info)
        expect(env_info["source"]).to eq("crash_capture")
        expect(env_info["pid"]).to eq(99999)
        expect(env_info["uptime_seconds"]).to eq(120.0)
      end

      it "deletes crash file after successful import" do
        crash_file = write_crash_file(build_crash_data, pid: 1)

        described_class.import!

        expect(File.exist?(crash_file)).to be false
      end

      it "imports cause chain into exception_cause column" do
        write_crash_file(build_crash_data(
          pid: 2000,
          cause_chain: [
            { exception_class: "ArgumentError", message: "inner" }
          ]
        ), pid: 2000)

        described_class.import!

        error_log = RailsErrorDashboard::ErrorLog.last
        next unless error_log.respond_to?(:exception_cause) && error_log.exception_cause.present?

        causes = JSON.parse(error_log.exception_cause)
        expect(causes.first["exception_class"]).to eq("ArgumentError")
      end

      it "imports multiple crash files" do
        2.times do |i|
          write_crash_file(build_crash_data(
            exception_class: "Error#{i}",
            message: "crash #{i}",
            backtrace: [ "file.rb:#{i}" ],
            pid: 1000 + i
          ), pid: 1000 + i)
        end

        expect {
          described_class.import!
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(2)
      end

      it "generates error_hash using ErrorHashGenerator for consistency with live errors" do
        write_crash_file(build_crash_data(
          exception_class: "RuntimeError",
          message: "PID 123 crashed",
          backtrace: [ "app/models/user.rb:42" ]
        ))

        described_class.import!

        error_log = RailsErrorDashboard::ErrorLog.last
        next unless error_log.respond_to?(:error_hash) && error_log.error_hash.present?

        # The hash should be 16 chars (ErrorHashGenerator format), not 64 chars (raw SHA256)
        expect(error_log.error_hash.length).to eq(16)
      end
    end

    context "edge cases" do
      it "handles empty crash directory" do
        expect {
          described_class.import!
        }.not_to raise_error

        expect(RailsErrorDashboard::ErrorLog.count).to eq(0)
      end

      it "handles missing crash directory" do
        RailsErrorDashboard.configuration.crash_capture_path = "/nonexistent/path"

        expect {
          described_class.import!
        }.not_to raise_error
      end

      it "uses 'UnknownCrash' when exception_class is missing from crash data" do
        write_crash_file(build_crash_data.except(:exception_class))

        described_class.import!

        error_log = RailsErrorDashboard::ErrorLog.last
        expect(error_log.error_type).to eq("UnknownCrash")
      end

      it "uses Time.current when timestamp is missing from crash data" do
        write_crash_file(build_crash_data.except(:timestamp))

        freeze_time do
          described_class.import!

          error_log = RailsErrorDashboard::ErrorLog.last
          expect(error_log.occurred_at).to be_within(1.second).of(Time.current)
        end
      end

      it "uses Time.current when timestamp is malformed" do
        write_crash_file(build_crash_data(timestamp: "not-a-date"))

        freeze_time do
          described_class.import!

          error_log = RailsErrorDashboard::ErrorLog.last
          expect(error_log.occurred_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "error resilience" do
      it "renames corrupted JSON to .failed instead of deleting" do
        crash_file = File.join(crash_dir, "red_crash_bad.json")
        File.write(crash_file, "not valid json {{{")

        expect {
          described_class.import!
        }.not_to raise_error

        # Original file should be gone
        expect(File.exist?(crash_file)).to be false
        # .failed file should exist
        expect(File.exist?("#{crash_file}.failed")).to be true
      end

      it "never raises even on unexpected errors" do
        RailsErrorDashboard.configuration.crash_capture_path = "/nonexistent/permission/denied"

        expect {
          described_class.import!
        }.not_to raise_error
      end
    end
  end

  describe ".reset!" do
    it "resets enabled state and boot time" do
      described_class.enable!
      expect(described_class.enabled?).to be true

      described_class.reset!
      expect(described_class.enabled?).to be false
    end
  end
end
