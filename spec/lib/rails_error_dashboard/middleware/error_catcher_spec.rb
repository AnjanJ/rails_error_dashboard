# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Middleware::ErrorCatcher do
  let(:app) { ->(env) { [ 200, {}, [ "OK" ] ] } }
  let(:middleware) { described_class.new(app) }
  let(:env) { Rack::MockRequest.env_for("/test") }
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  after do
    Thread.current[:rails_error_dashboard_request_env] = nil
    Thread.current[:rails_error_dashboard_reported_errors] = nil
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
  end

  describe "request env thread-local" do
    it "stores request env in Thread.current during the request" do
      env_during_request = nil
      app_spy = lambda do |_env|
        env_during_request = Thread.current[:rails_error_dashboard_request_env]
        [ 200, {}, [ "OK" ] ]
      end
      middleware = described_class.new(app_spy)

      middleware.call(env)

      expect(env_during_request).to eq(env)
    end

    it "clears request env after a successful request" do
      middleware.call(env)

      expect(Thread.current[:rails_error_dashboard_request_env]).to be_nil
    end

    it "clears request env after an exception" do
      error_app = ->(_env) { raise StandardError, "boom" }
      error_middleware = described_class.new(error_app)

      expect { error_middleware.call(env) }.to raise_error(StandardError)
      expect(Thread.current[:rails_error_dashboard_request_env]).to be_nil
    end

    it "clears reported errors set after a successful request" do
      Thread.current[:rails_error_dashboard_reported_errors] = Set.new([ 12345 ])
      middleware.call(env)

      expect(Thread.current[:rails_error_dashboard_reported_errors]).to be_nil
    end

    it "clears reported errors set after an exception" do
      Thread.current[:rails_error_dashboard_reported_errors] = Set.new([ 12345 ])
      error_app = ->(_env) { raise StandardError, "boom" }
      error_middleware = described_class.new(error_app)

      expect { error_middleware.call(env) }.to raise_error(StandardError)
      expect(Thread.current[:rails_error_dashboard_reported_errors]).to be_nil
    end
  end

  describe "breadcrumb integration" do
    context "when breadcrumbs enabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = true
      end

      it "initializes breadcrumb buffer at request start" do
        buffer_during_request = nil
        app_spy = lambda do |env|
          buffer_during_request = collector.current_buffer
          [ 200, {}, [ "OK" ] ]
        end
        middleware = described_class.new(app_spy)

        middleware.call(env)

        expect(buffer_during_request).to be_a(collector::RingBuffer)
      end

      it "clears buffer after successful request" do
        middleware.call(env)
        expect(Thread.current[:red_breadcrumbs]).to be_nil
      end

      it "clears buffer after exception" do
        error_app = ->(_env) { raise StandardError, "boom" }
        error_middleware = described_class.new(error_app)

        expect { error_middleware.call(env) }.to raise_error(StandardError)
        expect(Thread.current[:red_breadcrumbs]).to be_nil
      end
    end

    context "when breadcrumbs disabled" do
      before do
        RailsErrorDashboard.configuration.enable_breadcrumbs = false
      end

      it "does not initialize breadcrumb buffer" do
        buffer_during_request = nil
        app_spy = lambda do |env|
          buffer_during_request = collector.current_buffer
          [ 200, {}, [ "OK" ] ]
        end
        middleware = described_class.new(app_spy)

        middleware.call(env)

        expect(buffer_during_request).to be_nil
      end
    end
  end
end
