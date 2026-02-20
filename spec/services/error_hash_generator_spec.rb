# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ErrorHashGenerator do
  let(:exception) do
    begin
      raise StandardError, "Test error"
    rescue => e
      e
    end
  end

  describe ".call" do
    it "returns a 16-character hex hash" do
      result = described_class.call(exception)
      expect(result).to be_a(String)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[0-9a-f]{16}\z/)
    end

    it "returns the same hash for the same exception" do
      hash1 = described_class.call(exception)
      hash2 = described_class.call(exception)
      expect(hash1).to eq(hash2)
    end

    it "returns different hashes for different error types" do
      other = begin
        raise ArgumentError, "Test error"
      rescue => e
        e
      end

      hash1 = described_class.call(exception)
      hash2 = described_class.call(other)
      expect(hash1).not_to eq(hash2)
    end

    it "includes controller and action in hash" do
      hash_without = described_class.call(exception)
      hash_with = described_class.call(exception, controller_name: "users", action_name: "show")
      expect(hash_without).not_to eq(hash_with)
    end

    it "includes application_id in hash" do
      hash1 = described_class.call(exception, application_id: 1)
      hash2 = described_class.call(exception, application_id: 2)
      expect(hash1).not_to eq(hash2)
    end

    context "with custom_fingerprint configured" do
      after { RailsErrorDashboard.reset_configuration! }

      it "uses the custom fingerprint lambda" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(ex, _ctx) { "custom:#{ex.class.name}" }
        end

        hash1 = described_class.call(exception)

        # Same exception should produce same hash
        hash2 = described_class.call(exception)
        expect(hash1).to eq(hash2)

        # Should be a valid 16-char hex hash (SHA256 of custom key)
        expect(hash1.length).to eq(16)
        expect(hash1).to match(/\A[0-9a-f]{16}\z/)
      end

      it "passes context to the custom fingerprint lambda" do
        received_context = nil
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(_ex, ctx) {
            received_context = ctx
            "fingerprint"
          }
        end

        context = { controller_name: "users", action_name: "show" }
        described_class.call(exception, context: context)

        expect(received_context).to eq(context)
      end

      it "groups different exceptions together when fingerprint matches" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(_ex, _ctx) { "same-group" }
        end

        other = begin
          raise ArgumentError, "Different error"
        rescue => e
          e
        end

        hash1 = described_class.call(exception)
        hash2 = described_class.call(other)
        expect(hash1).to eq(hash2)
      end

      it "separates exceptions when fingerprint differs" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(ex, _ctx) { ex.message }
        end

        other = begin
          raise StandardError, "Different message"
        rescue => e
          e
        end

        hash1 = described_class.call(exception)
        hash2 = described_class.call(other)
        expect(hash1).not_to eq(hash2)
      end

      it "falls back to default when lambda returns nil" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(_ex, _ctx) { nil }
        end

        # Should still produce a valid hash (default behavior)
        hash = described_class.call(exception)
        expect(hash.length).to eq(16)
        expect(hash).to match(/\A[0-9a-f]{16}\z/)
      end

      it "falls back to default when lambda returns empty string" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(_ex, _ctx) { "" }
        end

        hash = described_class.call(exception)
        expect(hash.length).to eq(16)
        expect(hash).to match(/\A[0-9a-f]{16}\z/)
      end

      it "falls back to default when lambda raises an error" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(_ex, _ctx) { raise "boom" }
        end

        # Should not raise and should fall back to default
        hash = described_class.call(exception)
        expect(hash.length).to eq(16)
        expect(hash).to match(/\A[0-9a-f]{16}\z/)
      end

      it "ignores custom fingerprint for .from_attributes" do
        RailsErrorDashboard.configure do |config|
          config.custom_fingerprint = ->(_ex, _ctx) { "custom" }
        end

        # from_attributes is used by model callbacks and doesn't have an exception object
        hash = described_class.from_attributes(error_type: "StandardError", message: "test")
        expect(hash.length).to eq(16)
        expect(hash).to match(/\A[0-9a-f]{16}\z/)
      end
    end
  end

  describe ".from_attributes" do
    it "returns a 16-character hex hash" do
      result = described_class.from_attributes(error_type: "StandardError", message: "test")
      expect(result).to be_a(String)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  describe ".normalize_message" do
    it "replaces numbers" do
      result = described_class.normalize_message("User 123 not found")
      expect(result).to eq("User N not found")
    end

    it "replaces hex addresses" do
      result = described_class.normalize_message("Object at 0x7fff1234abcd")
      expect(result).to eq("Object at HEX")
    end

    it "replaces object inspections" do
      result = described_class.normalize_message('Got #<User:0x123> instead')
      expect(result).to eq("Got #<OBJ> instead")
    end

    it "handles nil" do
      result = described_class.normalize_message(nil)
      expect(result).to be_nil
    end
  end
end
