# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SeverityClassifier do
  describe ".classify" do
    it "returns :critical for critical error types" do
      %w[SecurityError NoMemoryError SystemStackError ActiveRecord::StatementInvalid].each do |type|
        expect(described_class.classify(type)).to eq(:critical), "Expected #{type} to be :critical"
      end
    end

    it "returns :high for high severity error types" do
      %w[ActiveRecord::RecordNotFound ArgumentError TypeError NoMethodError NameError].each do |type|
        expect(described_class.classify(type)).to eq(:high), "Expected #{type} to be :high"
      end
    end

    it "returns :medium for medium severity error types" do
      %w[ActiveRecord::RecordInvalid Timeout::Error Net::ReadTimeout JSON::ParserError].each do |type|
        expect(described_class.classify(type)).to eq(:medium), "Expected #{type} to be :medium"
      end
    end

    it "returns :low for unknown error types" do
      expect(described_class.classify("SomeRandomError")).to eq(:low)
      expect(described_class.classify("StandardError")).to eq(:low)
      expect(described_class.classify("RuntimeError")).to eq(:low)
    end

    context "with custom severity rules" do
      before do
        RailsErrorDashboard.configuration.custom_severity_rules["CustomPaymentError"] = "critical"
        RailsErrorDashboard.configuration.custom_severity_rules["ValidationError"] = "low"
      end

      after do
        RailsErrorDashboard.reset_configuration!
      end

      it "uses custom rule over default classification" do
        expect(described_class.classify("CustomPaymentError")).to eq(:critical)
        expect(described_class.classify("ValidationError")).to eq(:low)
      end

      it "custom rule overrides built-in classification" do
        # ArgumentError is normally :high, but custom rule says :low
        RailsErrorDashboard.configuration.custom_severity_rules["ArgumentError"] = "low"
        expect(described_class.classify("ArgumentError")).to eq(:low)
      ensure
        RailsErrorDashboard.reset_configuration!
      end
    end
  end

  describe ".critical?" do
    it "returns true for critical error types" do
      expect(described_class.critical?("SecurityError")).to be true
      expect(described_class.critical?("NoMemoryError")).to be true
    end

    it "returns false for non-critical error types" do
      expect(described_class.critical?("StandardError")).to be false
      expect(described_class.critical?("ArgumentError")).to be false
    end

    it "respects custom severity rules" do
      RailsErrorDashboard.configuration.custom_severity_rules["MyError"] = "critical"
      expect(described_class.critical?("MyError")).to be true
    ensure
      RailsErrorDashboard.reset_configuration!
    end
  end

  describe "constants" do
    it "has frozen constant arrays" do
      expect(described_class::CRITICAL_ERROR_TYPES).to be_frozen
      expect(described_class::HIGH_SEVERITY_ERROR_TYPES).to be_frozen
      expect(described_class::MEDIUM_SEVERITY_ERROR_TYPES).to be_frozen
    end

    it "contains expected error types" do
      expect(described_class::CRITICAL_ERROR_TYPES).to include("SecurityError")
      expect(described_class::HIGH_SEVERITY_ERROR_TYPES).to include("NoMethodError")
      expect(described_class::MEDIUM_SEVERITY_ERROR_TYPES).to include("Timeout::Error")
    end
  end
end
