# frozen_string_literal: true

require "rails_helper"

# The rate-limited line a capture-path failure writes (hardening-1-0-rc2,
# REQ-54 to REQ-57), with an injected clock. spec/integration/
# capture_failure_lines_spec.rb covers the same requirements through real
# failing captures. Spike S2: .shipkit/research/silent-failures-spike.md.
RSpec.describe RailsErrorDashboard::Services::CaptureFailureLog do
  let(:clock) { [ 1_000.0 ] }
  let(:failure_log) { described_class.new(clock: -> { clock[0] }) }
  let(:log) { StringIO.new }
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = Rails.logger
    logger = ActiveSupport::Logger.new(log)
    logger.level = :debug
    Rails.logger = logger
    example.run
  ensure
    Rails.logger = saved
  end

  before do
    config.log_level = :error
    config.enable_internal_logging = false
  end

  after { RailsErrorDashboard.reset_configuration! }

  def store_error(message = "store unavailable")
    ActiveRecord::StatementInvalid.new(message)
  end

  def lines = log.string.lines

  def summary_lines = lines.grep(/Capture failure in /)

  describe "the summary line (REQ-54)" do
    it "writes one line for 50 failures with one key, and the next, 60 s later, carries the suppressed count (hardening-1-0-rc2/REQ-54)" do
      50.times do
        failure_log.report("Commands::LogError#capture", store_error, ArgumentError.new("boom"))
        clock[0] += 1.0
      end

      expect(summary_lines.size).to eq(1)
      expect(summary_lines.first).to include("Commands::LogError#capture", "ActiveRecord::StatementInvalid",
                                             "ArgumentError", "0 suppressed")

      clock[0] = 1_060.0
      failure_log.report("Commands::LogError#capture", store_error, ArgumentError.new("boom"))

      expect(summary_lines.size).to eq(2)
      expect(summary_lines.last).to include("49 suppressed since the last line")
    end

    it "keeps suppressing until 60 s have passed since the last line, not since the last failure (hardening-1-0-rc2/REQ-54)" do
      failure_log.report("Commands::LogError#capture", store_error)
      clock[0] += 59.9
      failure_log.report("Commands::LogError#capture", store_error)

      expect(summary_lines.size).to eq(1)
    end

    it "writes a line for each failure class at one site, and for each site (hardening-1-0-rc2/REQ-54)" do
      failure_log.report("Commands::LogError#capture", store_error)
      failure_log.report("Commands::LogError#capture", ActiveRecord::ConnectionTimeoutError.new("no connection"))
      failure_log.report("Commands::LogError#maybe_notify", store_error)

      expect(summary_lines.size).to eq(3)
      expect(summary_lines[1]).to include("ActiveRecord::ConnectionTimeoutError")
      expect(summary_lines[2]).to include("Commands::LogError#maybe_notify")
    end

    it "keys a failure with no exception by the condition it names (hardening-1-0-rc2/REQ-54)" do
      2.times { failure_log.report("Services::CaptureWriteGuard.hold", "100 captures already wait") }

      expect(summary_lines.size).to eq(1)
      expect(summary_lines.first).to include("Services::CaptureWriteGuard.hold", "100 captures already wait")
    end

    it "tracks at most 100 keys, dropping the oldest (hardening-1-0-rc2/REQ-54)" do
      100.times { |i| failure_log.report("site #{i}", store_error) }
      failure_log.report("site 100", store_error)
      expect(summary_lines.size).to eq(101)

      clock[0] += 1.0
      failure_log.report("site 1", store_error) # still tracked: suppressed
      expect(summary_lines.size).to eq(101)

      failure_log.report("site 0", store_error) # dropped: a line again
      expect(summary_lines.size).to eq(102)
      expect(summary_lines.last).to include("site 0")
    end

    # The one part of RED's log wording 1.x keeps (.shipkit/decisions/0011,
    # docs/PUBLIC_API.md "What's private").
    it "starts with the prefix 1.x keeps, so a host can alert on it (hardening-1-0-rc2/REQ-54)" do
      failure_log.report("Commands::LogError#capture", store_error)

      expect(lines.first).to start_with("[RailsErrorDashboard] Capture failure in Commands::LogError#capture: ")
    end

    it "names a job by its id when given one (hardening-1-0-rc2/REQ-60)" do
      failure_log.report("ApplicationJob retry_on (RailsErrorDashboard::AsyncErrorLoggingJob)", store_error,
                         job_id: "job-id-1234")

      expect(summary_lines.first).to include("job job-id-1234")
    end

    it "never raises (hardening-1-0-rc2/REQ-54)" do
      raising_logger = ActiveSupport::Logger.new(log)
      def raising_logger.error(*) = raise(IOError, "log device closed")
      Rails.logger = raising_logger
      expect { failure_log.report("site", store_error) }.not_to raise_error

      broken_clock = described_class.new(clock: -> { raise "clock broke" })
      expect { broken_clock.report("site", store_error) }.not_to raise_error

      config.enable_internal_logging = true
      config.log_level = :debug
      expect { failure_log.report("other site", store_error) { raise "detail broke" } }.not_to raise_error
      expect { failure_log.report(nil, nil, Object.new) }.not_to raise_error
      expect(failure_log.report("site", store_error)).to be_nil
    end
  end

  describe "what the summary line leaves out (REQ-55)" do
    it "carries no message, context, param, URL or backtrace (hardening-1-0-rc2/REQ-55)" do
      failure = ActiveRecord::NotNullViolation.new(
        "PG::NotNullViolation: ERROR: null value in column \"error_type\" violates not-null constraint\n" \
        "DETAIL: Failing row contains (4711, null, password=hunter2-secret, 203.0.113.77)."
      )
      failure.set_backtrace([ "/srv/app/vendor/bundle/gems/activerecord/lib/active_record.rb:1:in 'save'" ])
      reported = ArgumentError.new("checkout failed for raw.person@example.test")

      failure_log.report("Commands::LogError#capture", failure, reported) do
        [ "context: {request_url: \"/checkout?reset_token=RAWTOKEN\"}" ]
      end

      expect(summary_lines.size).to eq(1)
      expect(log.string).not_to include("hunter2-secret", "Failing row contains", "203.0.113.77",
                                        "raw.person@example.test", "checkout failed", "RAWTOKEN",
                                        "active_record.rb", "not-null constraint")
    end
  end

  describe "log_level :silent (REQ-56)" do
    it "writes nothing, and never builds the detail (hardening-1-0-rc2/REQ-56)" do
      config.log_level = :silent
      config.enable_internal_logging = true
      built = 0

      3.times { failure_log.report("Commands::LogError#capture", store_error) { built += 1; [ "detail" ] } }

      expect(log.string).to be_empty
      expect(built).to eq(0)
    end
  end

  describe "the detail (REQ-57)" do
    it "writes the detail of every failure with enable_internal_logging at :debug, under one summary line (hardening-1-0-rc2/REQ-57)" do
      config.enable_internal_logging = true
      config.log_level = :debug

      3.times do |i|
        failure_log.report("Commands::LogError#capture", store_error) { [ "detail line #{i}", nil, "second #{i}" ] }
      end

      expect(summary_lines.size).to eq(1)
      expect(lines.grep(/detail line \d/).size).to eq(3)
      expect(lines.grep(/second \d/).size).to eq(3)
    end

    it "doesn't build the detail at :debug without enable_internal_logging, or at :error with it (hardening-1-0-rc2/REQ-57)" do
      built = 0
      config.log_level = :debug
      failure_log.report("site a", store_error) { built += 1; [ "detail" ] }
      config.log_level = :error
      config.enable_internal_logging = true
      failure_log.report("site b", store_error) { built += 1; [ "detail" ] }

      expect(built).to eq(0)
      expect(summary_lines.size).to eq(2)
    end
  end

  describe ".report" do
    it "goes through one limiter for the whole process, which reset! empties (hardening-1-0-rc2/REQ-54)" do
      2.times { described_class.report("Commands::LogError#capture", store_error) }
      expect(summary_lines.size).to eq(1)

      described_class.reset!
      described_class.report("Commands::LogError#capture", store_error)
      expect(summary_lines.size).to eq(2)
    end
  end
end
