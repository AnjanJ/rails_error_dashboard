# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ExceptionFilter do
  after { RailsErrorDashboard.reset_configuration! }

  describe ".should_log?" do
    it "returns true for a normal exception" do
      expect(described_class.should_log?(StandardError.new("test"))).to be true
    end

    it "returns false for an ignored exception" do
      RailsErrorDashboard.configure { |c| c.ignored_exceptions = [ "StandardError" ] }

      expect(described_class.should_log?(StandardError.new("test"))).to be false
    end

    it "returns false when sampled out" do
      RailsErrorDashboard.configure { |c| c.sampling_rate = 0.0 }

      expect(described_class.should_log?(StandardError.new("test"))).to be false
    end
  end

  describe ".ignored?" do
    it "returns false when no ignored exceptions configured" do
      expect(described_class.ignored?(StandardError.new("test"))).to be false
    end

    it "matches by class name string" do
      RailsErrorDashboard.configure { |c| c.ignored_exceptions = [ "ArgumentError" ] }

      expect(described_class.ignored?(ArgumentError.new("bad arg"))).to be true
      expect(described_class.ignored?(StandardError.new("other"))).to be false
    end

    it "matches by regex pattern" do
      RailsErrorDashboard.configure { |c| c.ignored_exceptions = [ /Argument/ ] }

      expect(described_class.ignored?(ArgumentError.new("bad"))).to be true
      expect(described_class.ignored?(TypeError.new("bad"))).to be false
    end

    it "supports inheritance matching for string class names" do
      RailsErrorDashboard.configure { |c| c.ignored_exceptions = [ "StandardError" ] }

      # ArgumentError inherits from StandardError
      expect(described_class.ignored?(ArgumentError.new("bad"))).to be true
    end

    it "handles invalid class names gracefully" do
      RailsErrorDashboard.configure { |c| c.ignored_exceptions = [ "NonExistentClass" ] }

      expect(described_class.ignored?(StandardError.new("test"))).to be false
    end
  end

  describe ".sampled_out?" do
    it "returns false when sampling rate is 1.0" do
      RailsErrorDashboard.configure { |c| c.sampling_rate = 1.0 }

      expect(described_class.sampled_out?(StandardError.new("test"))).to be false
    end

    it "returns true when sampling rate is 0.0 for non-critical errors" do
      RailsErrorDashboard.configure { |c| c.sampling_rate = 0.0 }

      expect(described_class.sampled_out?(StandardError.new("test"))).to be true
    end

    it "never samples out critical errors even at 0% rate" do
      RailsErrorDashboard.configure { |c| c.sampling_rate = 0.0 }

      critical = SecurityError.new("critical")
      expect(described_class.sampled_out?(critical)).to be false
    end
  end

  describe ".critical?" do
    it "returns true for critical error types" do
      expect(described_class.critical?(SecurityError.new("breach"))).to be true
      expect(described_class.critical?(NoMemoryError.new("oom"))).to be true
    end

    it "returns false for non-critical error types" do
      expect(described_class.critical?(StandardError.new("test"))).to be false
      expect(described_class.critical?(ArgumentError.new("bad"))).to be false
    end
  end
end
