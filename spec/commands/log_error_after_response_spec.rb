# frozen_string_literal: true

require "rails_helper"

# release-1-0-rc1/REQ-5, release-1-0-rc1/REQ-6, release-1-0-rc1/REQ-7
# (decision 0009).
#
# Async capture builds the job's arguments on the request thread, then hands
# only the enqueue to the server's rack.response_finished callbacks, so the
# queue's round trips (seven statements with Solid Queue on PostgreSQL) come
# after the response instead of before it. Without the hook, or outside a
# request, the enqueue stays inline.
RSpec.describe "async capture after the response" do
  let(:job_class) { RailsErrorDashboard::AsyncErrorLoggingJob }
  let(:logs) { RailsErrorDashboard::ErrorLog }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.async_logging = true
    config.enable_storm_protection = false
    config.sampling_rate = 1.0
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
    Thread.current[:rails_error_dashboard_request_env] = nil
  end

  after do
    Thread.current[:rails_error_dashboard_request_env] = nil
    RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  def boom(message = "after response boom")
    StandardError.new(message).tap do |e|
      e.set_backtrace([ "#{Rails.root}/app/models/order.rb:12:in 'save'" ])
    end
  end

  def rack_env(with_hook: true)
    env = Rack::MockRequest.env_for("/orders/1")
    env["rack.response_finished"] = [] if with_hook
    env
  end

  # What Puma 8 does once the response is written: each callable, in reverse,
  # with env, status, headers and error.
  def finish_response(env, status: 500, error: nil)
    env["rack.response_finished"].reverse_each { |callable| callable.call(env, status, {}, error) }
  end

  # Capture as a request does: ErrorCatcher keeps the env in the thread-local
  # for the whole request and clears it in its ensure.
  def capture_during_request(env, exception = boom)
    Thread.current[:rails_error_dashboard_request_env] = env
    RailsErrorDashboard::Commands::LogError.call(exception, {})
  ensure
    Thread.current[:rails_error_dashboard_request_env] = nil
  end

  describe "while the request's env has rack.response_finished (REQ-5)" do
    it "enqueues nothing before the response, then one job once the callbacks run" do
      env = rack_env

      capture_during_request(env)

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(0)
      expect(env["rack.response_finished"].size).to eq(1)

      finish_response(env)

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end

    it "stores the error once the queued job runs" do
      env = rack_env
      capture_during_request(env)
      finish_response(env)

      expect { perform_enqueued_jobs }.to change(logs, :count).by(1)
      expect(logs.last.message).to eq("after response boom")
    end

    it "runs the callback when the request itself failed, as the server does" do
      env = rack_env
      capture_during_request(env)
      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(0)

      finish_response(env, status: nil, error: boom("write failed"))

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end

    # The design defers only the enqueue. Everything the job carries is read
    # on the request thread, because ErrorCatcher's ensure clears the
    # breadcrumb buffer and the env before any callback runs.
    it "builds the job's arguments before the response, from the request's own state" do
      RailsErrorDashboard.configuration.enable_breadcrumbs = true
      RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
      RailsErrorDashboard::Services::BreadcrumbCollector.add("custom", "checkout started")
      env = rack_env

      capture_during_request(env)
      RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
      finish_response(env)
      perform_enqueued_jobs

      expect(logs.last.breadcrumbs).to include("checkout started")
    end
  end

  describe "where there is no hook to defer to (REQ-6)" do
    it "enqueues at once outside a request" do
      RailsErrorDashboard::Commands::LogError.call(boom, {})

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end

    it "enqueues at once when the env has no rack.response_finished" do
      capture_during_request(rack_env(with_hook: false))

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end

    it "enqueues at once when rack.response_finished is not an array" do
      env = rack_env(with_hook: false)
      env["rack.response_finished"] = {}

      capture_during_request(env)

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end

    it "enqueues at once when rack.response_finished is frozen" do
      env = rack_env(with_hook: false)
      env["rack.response_finished"] = [].freeze

      capture_during_request(env)

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end

    it "keeps sync capture synchronous, hook or not" do
      RailsErrorDashboard.configuration.async_logging = false
      env = rack_env

      expect { capture_during_request(env) }.to change(logs, :count).by(1)
      expect(env["rack.response_finished"]).to be_empty
    end
  end

  describe "when the deferred enqueue fails (REQ-7)" do
    it "logs the error synchronously from the callback when the enqueue raises" do
      allow(job_class).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue store down")
      env = rack_env

      expect { capture_during_request(env) }.not_to change(logs, :count)
      expect { finish_response(env) }.to change(logs, :count).by(1)
      expect(logs.last.message).to eq("after response boom")
    end

    it "logs the error synchronously from the callback when the enqueue returns false" do
      allow(job_class).to receive(:perform_later).and_return(false)
      env = rack_env

      expect { capture_during_request(env) }.not_to change(logs, :count)
      expect { finish_response(env) }.to change(logs, :count).by(1)
    end

    it "raises nothing into the server even when the fallback fails too" do
      allow(job_class).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue store down")
      allow_any_instance_of(RailsErrorDashboard::Commands::LogError)
        .to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished, "database down")
      allow(RailsErrorDashboard::Logger).to receive(:error)
      env = rack_env
      capture_during_request(env)

      expect { finish_response(env) }.not_to raise_error
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/database down/).at_least(:once)
    end
  end

  # ErrorCatcher keeps the env in a thread-local, and Puma reuses threads.
  describe "two requests on one thread" do
    let(:failing_app) { ->(_env) { raise StandardError, "request failed" } }
    let(:middleware) { RailsErrorDashboard::Middleware::ErrorCatcher.new(failing_app) }

    def request_through_middleware(env)
      middleware.call(env)
    rescue StandardError
      nil
    end

    it "hands each request's capture to that request's callbacks only" do
      first = rack_env
      second = rack_env

      request_through_middleware(first)
      finish_response(first)
      request_through_middleware(second)

      expect(first["rack.response_finished"].size).to eq(1)
      expect(second["rack.response_finished"].size).to eq(1)
      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)

      finish_response(second)

      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(2)
    end

    it "enqueues inline for a later capture on the thread outside any request" do
      env = rack_env
      request_through_middleware(env)

      RailsErrorDashboard::Commands::LogError.call(boom("from a job"), {})

      expect(env["rack.response_finished"].size).to eq(1)
      expect(enqueued_jobs.count { |j| j[:job] == job_class }).to eq(1)
    end
  end
end
