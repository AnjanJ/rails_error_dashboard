# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SensitiveDataFilter do
  before do
    described_class.reset!
    RailsErrorDashboard.configuration.filter_sensitive_data = false
    RailsErrorDashboard.configuration.sensitive_data_patterns = []
  end

  after do
    described_class.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".filter_attributes" do
    let(:attributes) do
      {
        message: "Test error",
        request_params: '{"username":"alice","password":"secret123","email":"alice@example.com"}',
        request_url: "/login?password=secret123&username=alice",
        exception_cause: '[{"class_name":"StandardError","message":"password=secret123"}]'
      }
    end

    context "when filtering is disabled" do
      it "returns attributes unchanged" do
        result = described_class.filter_attributes(attributes)
        expect(result).to eq(attributes)
      end
    end

    context "when filtering is enabled" do
      before do
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        # Simulate Rails filter_parameters (empty — defaults should still filter password)
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
      end

      it "filters password from request_params JSON via default patterns" do
        result = described_class.filter_attributes(attributes)
        parsed = JSON.parse(result[:request_params])

        expect(parsed["password"]).to eq("[FILTERED]")
        expect(parsed["username"]).to eq("alice")
        expect(parsed["email"]).to eq("alice@example.com")
      end

      it "filters password from request_url query string" do
        result = described_class.filter_attributes(attributes)

        # Rack::Utils.build_query URL-encodes brackets
        expect(result[:request_url]).to include("password=")
        expect(result[:request_url]).to include("username=alice")
        expect(result[:request_url]).not_to include("secret123")
      end

      it "preserves URL path when filtering query string" do
        result = described_class.filter_attributes(attributes)
        expect(result[:request_url]).to start_with("/login?")
      end

      it "filters key=value patterns in message" do
        attrs = attributes.merge(message: "Login failed: password=secret123 for user")
        result = described_class.filter_attributes(attrs)

        expect(result[:message]).to include("password=[FILTERED]")
        expect(result[:message]).not_to include("secret123")
      end

      it "filters cause chain messages" do
        result = described_class.filter_attributes(attributes)
        parsed = JSON.parse(result[:exception_cause])

        expect(parsed.first["message"]).to include("[FILTERED]")
        expect(parsed.first["message"]).not_to include("secret123")
      end

      it "filters default patterns without any Rails filter_parameters" do
        attrs = {
          message: "Test",
          request_params: '{"api_key":"ak_123","token":"tok_456","ssn":"123-45-6789","name":"alice"}',
          request_url: nil,
          exception_cause: nil
        }

        result = described_class.filter_attributes(attrs)
        parsed = JSON.parse(result[:request_params])

        expect(parsed["api_key"]).to eq("[FILTERED]")
        expect(parsed["token"]).to eq("[FILTERED]")
        expect(parsed["ssn"]).to eq("[FILTERED]")
        expect(parsed["name"]).to eq("alice")
      end

      it "filters credit card numbers from request_params" do
        attrs = {
          message: "Test",
          request_params: '{"credit_card":"4111111111111111","name":"alice"}',
          request_url: nil,
          exception_cause: nil
        }

        result = described_class.filter_attributes(attrs)
        parsed = JSON.parse(result[:request_params])

        expect(parsed["credit_card"]).to eq("[FILTERED]")
        expect(parsed["name"]).to eq("alice")
      end

      it "scrubs credit card numbers from free text in messages" do
        attrs = attributes.merge(message: "Payment failed for card 4111-1111-1111-1111 at checkout")
        result = described_class.filter_attributes(attrs)

        expect(result[:message]).not_to include("4111")
        expect(result[:message]).to include("[FILTERED]")
        expect(result[:message]).to include("Payment failed")
        expect(result[:message]).to include("at checkout")
      end

      it "scrubs credit card numbers with spaces from messages" do
        attrs = attributes.merge(message: "Card number: 4111 1111 1111 1111 is invalid")
        result = described_class.filter_attributes(attrs)

        expect(result[:message]).not_to include("4111")
        expect(result[:message]).to include("[FILTERED]")
      end

      it "filters session and auth tokens from params" do
        attrs = {
          message: "Test",
          request_params: '{"session_id":"abc123","access_token":"at_secret","cvv":"123","public":"visible"}',
          request_url: nil,
          exception_cause: nil
        }

        result = described_class.filter_attributes(attrs)
        parsed = JSON.parse(result[:request_params])

        expect(parsed["session_id"]).to eq("[FILTERED]")
        expect(parsed["access_token"]).to eq("[FILTERED]")
        expect(parsed["cvv"]).to eq("[FILTERED]")
        expect(parsed["public"]).to eq("visible")
      end

      it "handles nil request_params" do
        attrs = attributes.merge(request_params: nil)
        result = described_class.filter_attributes(attrs)
        expect(result[:request_params]).to be_nil
      end

      it "handles nil request_url" do
        attrs = attributes.merge(request_url: nil)
        result = described_class.filter_attributes(attrs)
        expect(result[:request_url]).to be_nil
      end

      it "handles nil message" do
        attrs = attributes.merge(message: nil)
        result = described_class.filter_attributes(attrs)
        expect(result[:message]).to be_nil
      end

      it "handles nil exception_cause" do
        attrs = attributes.merge(exception_cause: nil)
        result = described_class.filter_attributes(attrs)
        expect(result[:exception_cause]).to be_nil
      end

      it "handles malformed JSON in request_params" do
        attrs = attributes.merge(request_params: "not-json{{{")
        result = described_class.filter_attributes(attrs)
        # Should return original value on parse failure
        expect(result[:request_params]).to eq("not-json{{{")
      end

      it "handles malformed JSON in exception_cause" do
        attrs = attributes.merge(exception_cause: "not-json")
        result = described_class.filter_attributes(attrs)
        expect(result[:exception_cause]).to eq("not-json")
      end

      it "handles URL without query string" do
        attrs = attributes.merge(request_url: "/users/123")
        result = described_class.filter_attributes(attrs)
        expect(result[:request_url]).to eq("/users/123")
      end

      it "does not modify the original attributes hash" do
        original_params = attributes[:request_params].dup
        described_class.filter_attributes(attributes)
        expect(attributes[:request_params]).to eq(original_params)
      end
    end

    context "with custom sensitive_data_patterns" do
      before do
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        RailsErrorDashboard.configuration.sensitive_data_patterns = [ :employee_id, /internal_code/i ]
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
      end

      it "filters custom patterns in addition to built-in defaults" do
        attrs = {
          message: "Test",
          request_params: '{"password":"pw123","employee_id":"E456","name":"alice"}',
          request_url: "/api?employee_id=E456",
          exception_cause: nil
        }

        result = described_class.filter_attributes(attrs)
        parsed = JSON.parse(result[:request_params])

        expect(parsed["password"]).to eq("[FILTERED]")    # from defaults
        expect(parsed["employee_id"]).to eq("[FILTERED]")  # from custom
        expect(parsed["name"]).to eq("alice")
      end

      it "filters regex patterns" do
        attrs = {
          message: "Test",
          request_params: '{"internal_code_ref":"abc123","public_data":"visible"}',
          request_url: nil,
          exception_cause: nil
        }

        result = described_class.filter_attributes(attrs)
        parsed = JSON.parse(result[:request_params])

        expect(parsed["internal_code_ref"]).to eq("[FILTERED]")
        expect(parsed["public_data"]).to eq("visible")
      end
    end

    context "fail-safe behavior" do
      before do
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
      end

      it "returns original attributes if filtering raises unexpectedly" do
        allow(described_class).to receive(:parameter_filter).and_raise(RuntimeError, "boom")

        result = described_class.filter_attributes(attributes)
        expect(result).to eq(attributes)
      end
    end
  end

  describe ".parameter_filter" do
    before do
      RailsErrorDashboard.configuration.filter_sensitive_data = true
      allow(Rails.application.config).to receive(:filter_parameters).and_return([])
    end

    it "returns an ActiveSupport::ParameterFilter" do
      result = described_class.parameter_filter
      expect(result).to be_a(ActiveSupport::ParameterFilter)
    end

    it "always returns a filter even without Rails filter_parameters" do
      result = described_class.parameter_filter
      expect(result).not_to be_nil
    end

    it "caches the filter instance" do
      first = described_class.parameter_filter
      second = described_class.parameter_filter
      expect(first).to equal(second)
    end
  end

  describe ".reset!" do
    it "clears the cached parameter filter" do
      RailsErrorDashboard.configuration.filter_sensitive_data = true
      allow(Rails.application.config).to receive(:filter_parameters).and_return([])

      first = described_class.parameter_filter
      described_class.reset!
      second = described_class.parameter_filter
      expect(first).not_to equal(second)
    end
  end
end
