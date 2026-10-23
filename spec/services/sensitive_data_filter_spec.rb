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

    # Filtering fails closed: a step that breaks stores [FILTERED], never the
    # raw value it was meant to clean. Grouping is unaffected, because the
    # fingerprint is taken before filtering.
    context "when filtering breaks (fails closed)" do
      let(:filtered_fields) { %i[message request_params request_url exception_cause] }

      before do
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
      end

      # capture-hardening-0-17/REQ-7
      it "stores [FILTERED] for every filtered field when the filter can't be built" do
        allow(described_class).to receive(:parameter_filter).and_return(nil)

        result = described_class.filter_attributes(attributes.merge(error_type: "PaymentError"))

        expect(result.slice(*filtered_fields).values).to all(eq("[FILTERED]"))
        expect(result[:error_type]).to eq("PaymentError")
      end

      # capture-hardening-0-17/REQ-6
      it "stores [FILTERED] for every filtered field when filtering raises" do
        allow(described_class).to receive(:parameter_filter).and_raise(RuntimeError, "boom")

        result = described_class.filter_attributes(attributes)

        expect(result.slice(*filtered_fields).values).to all(eq("[FILTERED]"))
      end

      it "leaves a filtered field that is absent or nil as it is" do
        allow(described_class).to receive(:parameter_filter).and_return(nil)

        expect(described_class.filter_attributes(message: "boom", request_url: nil))
          .to eq(message: "[FILTERED]", request_url: nil)
      end

      # capture-hardening-0-17/REQ-6: only a query Rack can't parse gets the
      # pair-by-pair fallback; any other failure in the URL step fails closed.
      it "stores [FILTERED] for the URL when its step raises for another reason" do
        filter = described_class.parameter_filter
        # Only the whole-query hash fails; per-key checks still work, so the
        # pair-by-pair fallback, if it ran, would succeed and keep the URL.
        allow(filter).to receive(:filter).and_wrap_original do |original, value|
          raise "boom" if value.is_a?(Hash) && value.size > 1

          original.call(value)
        end

        expect(described_class.filter_attributes(request_url: "/login?password=x&username=alice")[:request_url])
          .to eq("[FILTERED]")
      end

      # capture-hardening-0-17/REQ-6
      it "stores [FILTERED] for the one field whose step raises, and filters the others" do
        filter = described_class.parameter_filter
        allow(filter).to receive(:filter).and_wrap_original do |original, value|
          raise "boom" if value.is_a?(Hash) && value.key?("email")

          original.call(value)
        end

        result = described_class.filter_attributes(attributes)

        expect(result[:request_params]).to eq("[FILTERED]")
        expect(result[:request_url]).to include("password=%5BFILTERED%5D", "username=alice")
        expect(result[:message]).to eq("Test error")
      end
    end

    # Free-text redaction is best-effort: these are the shapes it recognises.
    context "message shapes" do
      before do
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
      end

      def filtered_message(message)
        described_class.filter_attributes(message: message)[:message]
      end

      # capture-hardening-0-17/REQ-8
      it "redacts key: value for a sensitive key, quoted or not, and keeps other keys" do
        expect(filtered_message("login failed for password: hunter2 user: alice"))
          .to eq("login failed for password: [FILTERED] user: alice")
        expect(filtered_message('api_token: "two words"')).to eq("api_token: [FILTERED]")
      end

      # capture-hardening-0-17/REQ-8
      it "redacts JSON pairs, keeping the JSON well formed" do
        expect(filtered_message(%(unexpected token at '{"user":"a","token":"hunter2"'))).to eq(
          %(unexpected token at '{"user":"a","token":"[FILTERED]"')
        )
        expect(filtered_message(%({"pin": 1234, "id": 7}))).to eq(%({"pin": "[FILTERED]", "id": 7}))
      end

      # capture-hardening-0-17/REQ-9
      it "redacts a Bearer token" do
        expect(filtered_message("401 with Authorization: Bearer eyJhbGc.eyJzdWIi.sig-_x=="))
          .to eq("401 with Authorization: Bearer [FILTERED]")
      end

      # capture-hardening-0-17/REQ-9: a sensitive key in front of the token
      # must not hide it -- the key's pass stops at the first space, so it
      # would redact only the word "Bearer" and leave the token after it.
      it "redacts the token when a sensitive key comes before Bearer" do
        expect(filtered_message("retry with token: Bearer abc.def-ghi")).not_to include("abc.def-ghi")
        expect(filtered_message("retry with token=Bearer abc.def-ghi")).not_to include("abc.def-ghi")
        allow(Rails.application.config).to receive(:filter_parameters).and_return([ :authorization ])
        described_class.reset!
        expect(filtered_message("Authorization: Bearer abc.def-ghi")).not_to include("abc.def-ghi")
      end

      it "leaves ordinary text alone" do
        message = "undefined method 'name' for nil (NoMethodError) at https://example.com/a?b=c: retrying"
        expect(filtered_message(message)).to eq(message)
      end

      # capture-hardening-0-17/REQ-10
      it "redacts a URL whose query string can't be parsed, pair by pair" do
        result = described_class.filter_attributes(request_url: "/cb?token=hunter2&q=100%")[:request_url]

        expect(result).to eq("/cb?token=[FILTERED]&q=100%")
      end

      # capture-hardening-0-17/REQ-10
      it "redacts a URL with a bad %-escape, pair by pair" do
        result = described_class.filter_attributes(request_url: "/login?password=hunter2&x=%zz")[:request_url]

        expect(result).to eq("/login?password=[FILTERED]&x=%zz")
      end

      # capture-hardening-0-17/REQ-12: every pattern stays linear on
      # untrusted text; catastrophic backtracking would take seconds here.
      [
        [ "a word run", "a" * 10_000 ],
        [ "colon pairs", "a:" * 5_000 ],
        [ "equals pairs", "a=" * 5_000 ],
        [ "JSON keys", '"a":' * 2_500 ],
        [ "quotes", '"' * 10_000 ],
        [ "an unterminated JSON string", '{"token":"' + ("x" * 9_990) ],
        [ "unterminated quoted values", 'a: "' * 2_500 ],
        [ "Bearer runs", "Bearer " * 1_428 ],
        [ "many key: value matches", "a: b " * 2_000 ],
        [ "many JSON pairs", '"a":1,' * 1_666 ]
      ].each do |label, message|
        it "filters 10,000 characters of #{label} in under 50 ms" do
          described_class.filter_attributes(message: "warm up password: x")
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          described_class.filter_attributes(message: message)
          elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

          expect(elapsed_ms).to be < 50
        end
      end
    end

    # capture-hardening-0-17/REQ-11: text that isn't JSON is an input shape,
    # not a filter failure -- it gets the message rules rather than being
    # stored as it came, or thrown away.
    context "when params or the cause chain aren't JSON" do
      before do
        RailsErrorDashboard.configuration.filter_sensitive_data = true
        allow(Rails.application.config).to receive(:filter_parameters).and_return([])
      end

      it "redacts request params with the message rules" do
        result = described_class.filter_attributes(attributes.merge(request_params: "password=secret123 note=kept"))

        expect(result[:request_params]).to eq("password=[FILTERED] note=kept")
      end

      it "redacts a cause chain with the message rules" do
        result = described_class.filter_attributes(attributes.merge(exception_cause: "token=abc123 broke"))

        expect(result[:exception_cause]).to eq("token=[FILTERED] broke")
      end

      it "filters a JSON array of params" do
        result = described_class.filter_attributes(attributes.merge(request_params: '[{"password":"secret123","id":1}]'))

        expect(JSON.parse(result[:request_params])).to eq([ { "password" => "[FILTERED]", "id" => 1 } ])
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
