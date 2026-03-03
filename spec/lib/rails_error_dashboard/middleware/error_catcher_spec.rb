# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Middleware::ErrorCatcher do
  let(:app) { ->(env) { [ 200, {}, [ "OK" ] ] } }
  let(:middleware) { described_class.new(app) }
  let(:env) { Rack::MockRequest.env_for("/test") }
  let(:collector) { RailsErrorDashboard::Services::BreadcrumbCollector }

  after do
    collector.clear_buffer
    RailsErrorDashboard.reset_configuration!
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
