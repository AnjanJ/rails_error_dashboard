# frozen_string_literal: true

require "rails_helper"

# End-to-end test: fire one Commands::LogError.call with all four span kinds
# enabled, then assert that breadcrumb, health, and notification child spans
# emit alongside the parent capture span.
#
# NOTE on parent/child nesting: real parent/child relationships are tracked
# by OpenTelemetry::Context propagation, which requires the SDK to be active.
# Our fake provider doesn't implement context — so all four spans appear as
# siblings here. In a host app running opentelemetry-sdk with a real
# TracerProvider, the SDK's Context::set_value mechanism makes them properly
# nest. This spec verifies emission + attributes, not the nesting itself.
RSpec.describe "OTel outbound export end-to-end" do
  class E2eFakeSpan
    attr_reader :attributes

    def initialize(attributes: {})
      @attributes = attributes.dup
    end

    def set_attribute(key, value); @attributes[key] = value; self; end
    def add_event(_name, attributes: nil); self; end
    def record_exception(_exception, attributes: nil); self; end
    attr_accessor :status
    def context; nil; end
    def finish; self; end
  end

  class E2eFakeTracer
    attr_reader :spans
    def initialize; @spans = []; end
    def in_span(name, attributes: {})
      span = E2eFakeSpan.new(attributes: attributes)
      @spans << { name: name, span: span }
      yield span
    end
  end

  class E2eFakeProvider
    def initialize(tracer); @tracer = tracer; end
    def tracer(_name, _version = nil); @tracer; end
  end

  let(:tracer) { E2eFakeTracer.new }

  def install_otel(tracer:)
    provider = E2eFakeProvider.new(tracer)
    otel_module = Module.new
    otel_module.define_singleton_method(:tracer_provider) { provider }
    stub_const("OpenTelemetry", otel_module)

    status_class = Class.new do
      def self.error(message); new(:error, message); end
      attr_reader :code, :message
      def initialize(code, message); @code = code; @message = message; end
    end
    trace = Module.new
    trace.const_set(:Status, status_class)
    otel_module.const_set(:Trace, trace)
  end

  let(:exception) do
    begin
      raise StandardError, "end-to-end test"
    rescue => e
      e
    end
  end

  before do
    RailsErrorDashboard::Integrations::Tracer.reset!
    RailsErrorDashboard.configure do |c|
      c.async_logging = false
      c.enable_otel_export = true
      c.otel_spans = %i[capture breadcrumbs health notifications]
      c.application_name = "e2e-test"
      c.enable_breadcrumbs = true
      c.enable_system_health = true
      c.enable_slack_notifications = false
      c.enable_email_notifications = false
      c.enable_discord_notifications = false
      c.enable_pagerduty_notifications = false
      c.enable_webhook_notifications = false
    end
    install_otel(tracer: tracer)
    RailsErrorDashboard::Services::BreadcrumbCollector.init_buffer
  end

  after do
    RailsErrorDashboard::Services::BreadcrumbCollector.clear_buffer
    RailsErrorDashboard::Integrations::Tracer.reset!
    RailsErrorDashboard.reset_configuration!
  end

  def span_names; tracer.spans.map { |s| s[:name] }; end
  def span_named(name); tracer.spans.find { |s| s[:name] == name }&.dig(:span); end

  describe "with all four span kinds enabled" do
    before do
      # Add a few breadcrumbs so the breadcrumb_collection span carries data
      RailsErrorDashboard::Services::BreadcrumbCollector.add("sql", "SELECT 1", duration_ms: 0.5)
      RailsErrorDashboard::Services::BreadcrumbCollector.add("controller", "UsersController#show")
    end

    it "emits the parent capture_error span" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(span_names).to include("rails_error_dashboard.capture_error")
    end

    it "emits the breadcrumb_collection child span" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(span_names).to include("rails_error_dashboard.breadcrumb_collection")
    end

    it "tags breadcrumb_collection with breadcrumb_count and bytes_serialized_estimate" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = span_named("rails_error_dashboard.breadcrumb_collection")
      expect(span.attributes["breadcrumb_count"]).to eq(2)
      expect(span.attributes["bytes_serialized_estimate"]).to be > 0
    end

    it "emits the system_health_snapshot child span" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(span_names).to include("rails_error_dashboard.system_health_snapshot")
    end

    it "emits the notification_dispatch child span (with zero channels enabled)" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(span_names).to include("rails_error_dashboard.notification_dispatch")
      span = span_named("rails_error_dashboard.notification_dispatch")
      expect(span.attributes["channels"]).to eq([])
      expect(span.attributes["channel_count"]).to eq(0)
    end

    it "links notification_dispatch to the error_id" do
      result = RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = span_named("rails_error_dashboard.notification_dispatch")
      expect(span.attributes["rails_error_dashboard.error_id"]).to eq(result.id)
    end

    it "tags notification_dispatch with the channels that fired" do
      RailsErrorDashboard.configuration.enable_slack_notifications = true
      RailsErrorDashboard.configuration.slack_webhook_url = "https://example.test/webhook"
      allow(RailsErrorDashboard::SlackErrorNotificationJob).to receive(:perform_later)

      RailsErrorDashboard::Commands::LogError.call(exception, {})
      span = span_named("rails_error_dashboard.notification_dispatch")
      expect(span.attributes["channels"]).to eq([ "slack" ])
      expect(span.attributes["channel_count"]).to eq(1)
    end

    it "all spans carry the base attributes (version + service_name)" do
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      tracer.spans.each do |entry|
        attrs = entry[:span].attributes
        expect(attrs["rails_error_dashboard.version"]).to eq(RailsErrorDashboard::VERSION)
        expect(attrs["rails_error_dashboard.service_name"]).to eq("e2e-test")
      end
    end
  end

  describe "selective span kind opt-out" do
    it "only emits the capture span when otel_spans is [:capture]" do
      RailsErrorDashboard.configuration.otel_spans = %i[capture]
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(span_names).to eq([ "rails_error_dashboard.capture_error" ])
    end

    it "emits no spans when enable_otel_export is false" do
      RailsErrorDashboard.configuration.enable_otel_export = false
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(tracer.spans).to be_empty
    end

    it "emits no spans when otel_spans is empty" do
      RailsErrorDashboard.configuration.otel_spans = []
      RailsErrorDashboard::Commands::LogError.call(exception, {})
      expect(tracer.spans).to be_empty
    end

    it "ErrorLog is still created when all spans are opted out (transparency)" do
      RailsErrorDashboard.configuration.otel_spans = []
      expect {
        RailsErrorDashboard::Commands::LogError.call(exception, {})
      }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
    end
  end

  describe "host safety: feature works identically with OTel off" do
    it "produces the same ErrorLog regardless of enable_otel_export" do
      RailsErrorDashboard.configuration.enable_otel_export = false
      result_off = RailsErrorDashboard::Commands::LogError.call(exception, {})

      # Add a second error so the dedup key differs
      other_exception = begin
        raise StandardError, "second"
      rescue => e
        e
      end

      RailsErrorDashboard.configuration.enable_otel_export = true
      result_on = RailsErrorDashboard::Commands::LogError.call(other_exception, {})

      expect(result_off).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result_on).to be_a(RailsErrorDashboard::ErrorLog)
      expect(result_off.error_type).to eq("StandardError")
      expect(result_on.error_type).to eq("StandardError")
    end
  end
end
