# frozen_string_literal: true

require "rails_helper"

# What RED writes to the host's log when a capture fails, and what Active Job
# writes for RED's capture jobs, at the most verbose setting RED has.
#
# - A capture failure never prints the request's unfiltered params or URL
#   (hardening-1-0-rc2/REQ-59). The Context lines printed @context, which holds
#   request.params before RED filters them, at log_level :error.
# - Active Job doesn't log the capture jobs' arguments, and a job whose
#   retries run out is named by class and id (hardening-1-0-rc2/REQ-60).
#
# Spike S2: .shipkit/research/silent-failures-spike.md.
RSpec.describe "Failure log privacy" do
  # Rails' own template, config/initializers/filter_parameter_logging.rb. The
  # dummy app has none, and without it Rails' lines would show what RED hides.
  let(:template_filters) { %i[passw email secret token _key crypt salt certificate otp ssn cvv cvc] }

  let(:raw) do
    {
      password: "RAWPASSWORD-hunter2",
      card: "4111111111111111",
      email: "raw.person@example.test",
      token: "RAWRESETTOKEN987",
      user_id: "9876543",
      ip: "203.0.113.77",
      agent: "RawAgent/9.9"
    }
  end

  let(:log) { StringIO.new }

  around do |example|
    saved_rails_logger = Rails.logger
    saved_job_logger = ActiveJob::Base.logger
    saved_filters = Rails.application.config.filter_parameters.dup
    logger = ActiveSupport::Logger.new(log)
    logger.level = :debug
    Rails.logger = logger
    ActiveJob::Base.logger = logger
    Rails.application.config.filter_parameters.replace(template_filters)
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    example.run
  ensure
    Rails.logger = saved_rails_logger
    ActiveJob::Base.logger = saved_job_logger
    Rails.application.config.filter_parameters.replace(saved_filters)
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
  end

  before do
    RailsErrorDashboard.configuration.enable_internal_logging = true
    RailsErrorDashboard.configuration.log_level = :debug
  end

  def request
    env = Rack::MockRequest.env_for(
      "/checkout?reset_token=#{raw[:token]}",
      method: "POST",
      params: { user: { password: raw[:password], email: raw[:email] }, card_number: raw[:card] },
      "REMOTE_ADDR" => raw[:ip],
      "HTTP_USER_AGENT" => raw[:agent]
    )
    ActionDispatch::Request.new(env)
  end

  def boom
    error = ArgumentError.new("checkout failed")
    error.set_backtrace([ "#{Rails.root}/app/controllers/checkouts_controller.rb:7:in 'create'" ])
    error
  end

  def report(context)
    RailsErrorDashboard::ErrorReporter.new.report(boom, handled: false, severity: :error, context: context)
  end

  def leaked(keys = %i[password card email token])
    keys.select { |key| log.string.include?(raw[key]) }
  end

  it "leaves no raw param or URL value in the log when a sync capture's write fails (hardening-1-0-rc2/REQ-59)" do
    RailsErrorDashboard.configuration.async_logging = false
    connection = RailsErrorDashboard::ErrorLog.connection
    table = RailsErrorDashboard::ErrorLog.table_name
    connection.rename_table(table, "#{table}_hidden")
    begin
      expect(report(request: request, user_id: raw[:user_id])).to be_nil
    ensure
      connection.rename_table("#{table}_hidden", table)
      RailsErrorDashboard::ErrorLog.reset_column_information
    end

    # The failure was logged, so the check below reads the failure path.
    expect(log.string).to include("LogError command failed")
    expect(leaked).to be_empty
  end

  it "leaves no raw param or URL value in the log when ErrorReporter itself fails (hardening-1-0-rc2/REQ-59)" do
    current_user = Object.new
    def current_user.id = raise(NoMethodError, "id exploded")

    report(request: request, current_user: current_user)

    expect(log.string).to include("ErrorReporter failed")
    expect(leaked).to be_empty
  end

  it "doesn't let Active Job log the capture jobs' arguments (hardening-1-0-rc2/REQ-60)" do
    expect(RailsErrorDashboard::AsyncErrorLoggingJob.log_arguments?).to be false
    expect(RailsErrorDashboard::StormFlushJob.log_arguments?).to be false
  end

  it "enqueues an async capture with no user id, IP or user agent in the Enqueued line (hardening-1-0-rc2/REQ-60)" do
    RailsErrorDashboard.configuration.async_logging = true

    report(request: request, user_id: raw[:user_id])

    enqueued = log.string.lines.grep(/Enqueued .*AsyncErrorLoggingJob/)
    expect(enqueued).not_to be_empty
    expect(enqueued.join).not_to include(raw[:user_id], raw[:ip], raw[:agent])
    expect(leaked(%i[password card email token user_id ip agent])).to be_empty
  end

  it "names an exhausted capture job by class and id, with no argument value (hardening-1-0-rc2/REQ-60)" do
    exception_data = { class_name: "ArgumentError", message: "checkout failed", backtrace: boom.backtrace }
    context = { request_url: "/checkout?reset_token=#{raw[:token]}", user_id: raw[:user_id],
                ip_address: raw[:ip], user_agent: raw[:agent], request_params: { card_number: raw[:card] } }
    job = RailsErrorDashboard::AsyncErrorLoggingJob.new(exception_data, context)
    allow_any_instance_of(RailsErrorDashboard::Commands::LogError).to receive(:call)
      .and_raise(ActiveRecord::StatementInvalid, "store unavailable")
    # Two attempts already spent: this one is the last of retry_on's three.
    job.exception_executions = { "[StandardError]" => 2 }
    job.executions = 2

    job.perform_now

    expect(log.string).to include("Job RailsErrorDashboard::AsyncErrorLoggingJob failed")
    expect(log.string).to include(job.job_id)
    expect(log.string).not_to include("Job arguments")
    expect(leaked(%i[card token user_id ip agent])).to be_empty
  end
end
