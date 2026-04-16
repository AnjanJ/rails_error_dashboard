# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ErrorReporter do
  let(:reporter) { described_class.new }
  let(:error) { StandardError.new("test error") }
  let(:env) { Rack::MockRequest.env_for("/users?name=XXX", method: "GET") }

  before do
    error.set_backtrace([ "app/controllers/test_controller.rb:10" ])
  end

  after do
    Thread.current[:rails_error_dashboard_request_env] = nil
    Thread.current[:rails_error_dashboard_reported_errors] = nil
    RailsErrorDashboard.reset_configuration!
  end

  describe "#report" do
    context "when error from Rails internals inside an HTTP request" do
      before do
        Thread.current[:rails_error_dashboard_request_env] = env
      end

      it "enriches context with the request from Thread.current" do
        captured_context = nil
        allow(RailsErrorDashboard::Commands::LogError).to receive(:call) do |_err, ctx|
          captured_context = ctx
        end

        reporter.report(error,
          handled: false,
          severity: :error,
          context: {},
          source: "application.action_dispatch"
        )

        expect(captured_context[:request_url]).to include("/users")
      end

      it "captures request params from Thread.current" do
        captured_context = nil
        allow(RailsErrorDashboard::Commands::LogError).to receive(:call) do |_err, ctx|
          captured_context = ctx
        end

        reporter.report(error,
          handled: false,
          severity: :error,
          context: {},
          source: "application.action_dispatch"
        )

        expect(captured_context[:request_params]).to include("name")
      end

      it "does not override an existing request in context" do
        custom_env = Rack::MockRequest.env_for("/custom-path")
        custom_request = ActionDispatch::Request.new(custom_env)

        captured_context = nil
        allow(RailsErrorDashboard::Commands::LogError).to receive(:call) do |_err, ctx|
          captured_context = ctx
        end

        reporter.report(error,
          handled: false,
          severity: :error,
          context: { request: custom_request },
          source: "application.action_dispatch"
        )

        expect(captured_context[:request_url]).to eq("/custom-path")
      end
    end

    context "deduplication with middleware" do
      before do
        Thread.current[:rails_error_dashboard_request_env] = env
      end

      it "skips duplicate report from rack.middleware for same error" do
        # First report: subscriber captures error
        expect(RailsErrorDashboard::Commands::LogError).to receive(:call).once

        reporter.report(error,
          handled: false,
          severity: :error,
          context: {},
          source: "application.action_dispatch"
        )

        # Second report: middleware catches same error — should be skipped
        reporter.report(error,
          handled: false,
          severity: :error,
          context: { request: ActionDispatch::Request.new(env), middleware: true },
          source: "rack.middleware"
        )
      end

      it "does not skip middleware report for a different error" do
        other_error = RuntimeError.new("different error")
        other_error.set_backtrace([ "app/models/user.rb:5" ])

        expect(RailsErrorDashboard::Commands::LogError).to receive(:call).twice

        reporter.report(error,
          handled: false,
          severity: :error,
          context: {},
          source: "application.action_dispatch"
        )

        reporter.report(other_error,
          handled: false,
          severity: :error,
          context: { request: ActionDispatch::Request.new(env), middleware: true },
          source: "rack.middleware"
        )
      end

      it "does not skip non-middleware sources" do
        expect(RailsErrorDashboard::Commands::LogError).to receive(:call).twice

        reporter.report(error,
          handled: false,
          severity: :error,
          context: {},
          source: "application.action_dispatch"
        )

        # Same error reported from a different (non-middleware) source
        reporter.report(error,
          handled: false,
          severity: :error,
          context: {},
          source: "application.controller"
        )
      end
    end

    context "when outside an HTTP request (background job)" do
      before do
        Thread.current[:rails_error_dashboard_request_env] = nil
      end

      it "processes the report normally without enrichment" do
        captured_context = nil
        allow(RailsErrorDashboard::Commands::LogError).to receive(:call) do |_err, ctx|
          captured_context = ctx
        end

        reporter.report(error,
          handled: false,
          severity: :error,
          context: { job: double(class: double(name: "TestJob"), job_id: "123", queue_name: "default", arguments: [], executions: 0) },
          source: "active_job"
        )

        expect(captured_context[:request_url]).to include("Background Job")
      end
    end

    context "when source is rack.middleware without prior subscriber report" do
      before do
        Thread.current[:rails_error_dashboard_request_env] = env
      end

      it "processes the report (no prior report to dedup against)" do
        expect(RailsErrorDashboard::Commands::LogError).to receive(:call)

        reporter.report(error,
          handled: false,
          severity: :error,
          context: { request: ActionDispatch::Request.new(env), middleware: true },
          source: "rack.middleware"
        )
      end
    end

    it "skips handled warnings" do
      expect(RailsErrorDashboard::Commands::LogError).not_to receive(:call)

      reporter.report(error,
        handled: true,
        severity: :warning,
        context: {}
      )
    end

    it "does not propagate exceptions from error logging" do
      allow(RailsErrorDashboard::Commands::LogError).to receive(:call).and_raise(RuntimeError, "DB down")

      expect {
        reporter.report(error, handled: false, severity: :error, context: {})
      }.not_to raise_error
    end
  end
end
