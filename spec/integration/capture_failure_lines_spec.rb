# frozen_string_literal: true

require "rails_helper"

# What a failing capture writes to the host's log, path by path, 20 failures
# each: the paths spike S2 measured (.shipkit/research/silent-failures-spike.md).
#
# - At log_level :error, one summary line per key, the call site and the
#   failure's class, and nothing else (hardening-1-0-rc2/REQ-54).
# - At :silent, no line, the worker's included (hardening-1-0-rc2/REQ-56).
# - With enable_internal_logging at :debug, the detail of every failure, its
#   context filtered (hardening-1-0-rc2/REQ-57, hardening-1-0-rc2/REQ-59).
# - log_level defaults to :error (hardening-1-0-rc2/REQ-58).
#
# Active Job's own lines go to a log of their own: they are Active Job's, not
# RED's (REQ-60 covers what they carry, in failure_log_privacy_spec.rb).
#
# Committed rows (:non_transactional): the paths rename RED's table or a
# column, and DDL inside the test's transaction breaks it. MySQL commits it
# implicitly, so the cleaner's savepoint is gone; on PostgreSQL the first
# failed statement aborts the transaction, so the rename back fails.
RSpec.describe "Capture failure lines", :non_transactional do
  self.use_transactional_tests = false

  def failures = 20

  def run_sync_table_hidden
    config.async_logging = false
    with_table_hidden { failures.times { |i| report(i) } }
  end

  let(:template_filters) { %i[passw email secret token _key crypt salt certificate otp ssn cvv cvc] }
  let(:raw) do
    { password: "RAWPASSWORD-hunter2", card: "4111111111111111", email: "raw.person@example.test",
      token: "RAWRESETTOKEN987" }
  end
  let(:log) { StringIO.new }
  let(:job_log) { StringIO.new }
  let(:config) { RailsErrorDashboard.configuration }
  let(:connection) { RailsErrorDashboard::ErrorLog.connection }
  let(:table) { RailsErrorDashboard::ErrorLog.table_name }

  around do |example|
    saved = [ Rails.logger, ActiveJob::Base.logger, Rails.application.config.filter_parameters.dup ]
    Rails.logger = ActiveSupport::Logger.new(log).tap { _1.level = :debug }
    ActiveJob::Base.logger = ActiveSupport::Logger.new(job_log)
    Rails.application.config.filter_parameters.replace(template_filters)
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    example.run
  ensure
    Rails.logger, ActiveJob::Base.logger = saved[0], saved[1]
    Rails.application.config.filter_parameters.replace(saved[2])
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
  end

  after { RailsErrorDashboard.reset_configuration! }

  def request
    env = Rack::MockRequest.env_for(
      "/checkout?reset_token=#{raw[:token]}",
      method: "POST",
      params: { user: { password: raw[:password], email: raw[:email] }, card_number: raw[:card] },
      "HTTP_USER_AGENT" => "RawAgent/9.9"
    )
    ActionDispatch::Request.new(env)
  end

  def boom(index)
    error = ArgumentError.new("checkout failed #{index}")
    error.set_backtrace([ "#{Rails.root}/app/controllers/checkouts_controller.rb:7:in 'create'" ])
    error
  end

  def report(index)
    RailsErrorDashboard::ErrorReporter.new.report(boom(index), handled: false, severity: :error,
                                                  context: { request: request })
  end

  def capture_job(index)
    RailsErrorDashboard::AsyncErrorLoggingJob.new(
      { class_name: "ArgumentError", message: "checkout failed #{index}", backtrace: boom(index).backtrace },
      { request_url: "/checkout?reset_token=#{raw[:token]}", user_agent: "RawAgent/9.9",
        request_params: { card_number: raw[:card], user: { password: raw[:password] } }.to_json }
    )
  end

  def storm_entry
    { "error_class" => "StormError", "message" => "storm", "first_app_frame" => "app/models/s.rb",
      "controller_name" => "c", "action_name" => "a", "count" => 5,
      "first_seen_at" => Time.current.iso8601, "last_seen_at" => Time.current.iso8601 }
  end

  def with_table_hidden
    connection.rename_table(table, "#{table}_hidden")
    yield
  ensure
    connection.rename_table("#{table}_hidden", table)
    RailsErrorDashboard::ErrorLog.reset_column_information
  end

  # A column a migration didn't add, missing when the process booted: the
  # model doesn't know it, so assigning it raises ActiveModel::UnknownAttributeError.
  def with_column_missing_at_boot
    connection.rename_column(table, :user_agent, :user_agent_hidden)
    RailsErrorDashboard::ErrorLog.reset_column_information
    yield
  ensure
    connection.rename_column(table, :user_agent_hidden, :user_agent)
    RailsErrorDashboard::ErrorLog.reset_column_information
  end

  # Each path: what it runs `failures` times, and a line of its detail.
  paths = {
    "a sync capture with RED's table renamed" => {
      detail: "LogError command failed",
      run: lambda do |spec|
        spec.config.async_logging = false
        spec.with_table_hidden { spec.failures.times { |i| spec.report(i) } }
      end
    },
    "the async worker with RED's table renamed (retryable)" => {
      detail: "AsyncErrorLoggingJob: error storage unavailable",
      run: lambda do |spec|
        spec.with_table_hidden { spec.failures.times { |i| spec.capture_job(i).perform_now } }
      end
    },
    "the worker with a column missing at boot (payload error)" => {
      detail: "LogError command failed",
      run: lambda do |spec|
        spec.with_column_missing_at_boot { spec.failures.times { |i| spec.capture_job(i).perform_now } }
      end
    },
    "a capture job whose retries run out" => {
      detail: "Job RailsErrorDashboard::AsyncErrorLoggingJob failed",
      run: lambda do |spec|
        spec.with_table_hidden do
          spec.failures.times do |i|
            job = spec.capture_job(i)
            # Two attempts already spent: this one is the last of retry_on's three.
            job.exception_executions = { "[StandardError]" => 2 }
            job.executions = 2
            job.perform_now
          end
        end
      end
    },
    "a raising plugin" => {
      detail: "Plugin 'raising-plugin' failed in",
      run: lambda do |spec|
        spec.config.async_logging = false
        plugin = Class.new(RailsErrorDashboard::Plugin) do
          def name = "raising-plugin"
          def on_error_logged(_error_log) = raise(KeyError, "plugin broke")
          def on_error_recurred(_error_log) = raise(KeyError, "plugin broke")
        end.new
        RailsErrorDashboard::PluginRegistry.register(plugin)
        begin
          spec.failures.times { |i| spec.report(i) }
        ensure
          RailsErrorDashboard::PluginRegistry.unregister("raising-plugin")
        end
      end
    },
    "a raising custom_fingerprint" => {
      detail: "Custom fingerprint lambda failed",
      run: lambda do |spec|
        spec.config.async_logging = false
        spec.config.custom_fingerprint = ->(_exception, _context) { raise KeyError, "fingerprint broke" }
        spec.failures.times { |i| spec.report(i) }
      end
    },
    "a failing storm flush job" => {
      detail: "FlushStormCounts failed",
      run: lambda do |spec|
        spec.with_table_hidden do
          spec.failures.times do
            RailsErrorDashboard::StormFlushJob.new(entries: [ spec.storm_entry ], batch_id: SecureRandom.uuid).perform_now
          end
        end
      end
    }
  }.freeze

  def lines = log.string.lines

  def summary_lines = lines.grep(/Capture failure in /)

  # The call site and the failure's class, as the line names them.
  def keys = summary_lines.map { _1[/Capture failure in (.+?): ([\w:]+)/, 0] }

  def leaked = raw.values.select { log.string.include?(_1) }

  paths.each do |path, about|
    describe path do
      it "writes one summary line per key at log_level :error, and nothing else (hardening-1-0-rc2/REQ-54)" do
        config.log_level = :error
        about[:run].call(self)

        expect(summary_lines).not_to be_empty
        expect(keys.tally.values.uniq).to eq([ 1 ]), "lines per key: #{keys.tally}"
        expect(lines - summary_lines).to be_empty, "other lines:\n#{(lines - summary_lines).join}"
        expect(leaked).to be_empty
      end

      it "writes no line at log_level :silent (hardening-1-0-rc2/REQ-56)" do
        config.log_level = :silent
        config.enable_internal_logging = true
        about[:run].call(self)

        expect(log.string).to be_empty
      end

      it "writes the detail of every failure, its context filtered, with enable_internal_logging at :debug (hardening-1-0-rc2/REQ-57, hardening-1-0-rc2/REQ-59)" do
        config.log_level = :debug
        config.enable_internal_logging = true
        about[:run].call(self)

        expect(lines.grep(/#{Regexp.escape(about[:detail])}/).size).to eq(failures)
        expect(keys.tally.values.uniq).to eq([ 1 ])
        expect(leaked).to be_empty
      end
    end
  end

  it "prints a sync capture's context in the detail as RED stores it, filtered (hardening-1-0-rc2/REQ-57, hardening-1-0-rc2/REQ-59)" do
    config.log_level = :debug
    config.enable_internal_logging = true
    run_sync_table_hidden

    context_lines = lines.grep(/Context: /)
    expect(context_lines.size).to eq(failures)
    expect(context_lines.first).to include("/checkout", "[FILTERED]")
    expect(leaked).to be_empty
  end

  it "withholds the params and URL from the detail when the host turns filtering off (hardening-1-0-rc2/REQ-59)" do
    config.log_level = :debug
    config.enable_internal_logging = true
    config.filter_sensitive_data = false
    run_sync_table_hidden

    expect(lines.grep(/Context: /).size).to eq(failures)
    expect(leaked).to be_empty
  end

  it "defaults log_level to :error, in the library and in the installer's template (hardening-1-0-rc2/REQ-58)" do
    expect(RailsErrorDashboard::Configuration.new.log_level).to eq(:error)

    template = File.read(File.join(RailsErrorDashboard::Engine.root,
                                   "lib/generators/rails_error_dashboard/install/templates/initializer.rb"))
    set = template.lines.grep(/^\s*config\.log_level\s*=/)
    expect(set.map(&:strip)).to eq([ "config.log_level = :error" ])
  end
end
