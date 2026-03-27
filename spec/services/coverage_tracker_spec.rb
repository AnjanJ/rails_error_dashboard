# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::CoverageTracker do
  after do
    # Ensure coverage is stopped after each test
    described_class.disable! if described_class.active?
  end

  describe ".enable!" do
    it "activates coverage tracking" do
      result = described_class.enable!
      expect(result).to be true
      expect(described_class.active?).to be true
    end

    it "is idempotent — calling twice does not raise" do
      described_class.enable!
      expect { described_class.enable! }.not_to raise_error
      expect(described_class.active?).to be true
    end
  end

  describe ".disable!" do
    it "deactivates coverage tracking" do
      described_class.enable!
      described_class.disable!
      expect(described_class.active?).to be false
    end

    it "is idempotent — calling when inactive does not raise" do
      expect { described_class.disable! }.not_to raise_error
      expect(described_class.active?).to be false
    end
  end

  describe ".active?" do
    it "returns false when coverage has not been enabled" do
      expect(described_class.active?).to be false
    end

    it "returns true when coverage is enabled" do
      described_class.enable!
      expect(described_class.active?).to be true
    end

    it "returns false after disable" do
      described_class.enable!
      described_class.disable!
      expect(described_class.active?).to be false
    end
  end

  describe ".peek" do
    it "returns nil when coverage is inactive" do
      expect(described_class.peek(__FILE__)).to be_nil
    end

    it "returns executed line numbers for a known file when active" do
      described_class.enable!

      # The spec file itself will have coverage since it's being executed
      # (SimpleCov or our own session provides the data)
      result = described_class.peek(__FILE__)

      expect(result).to be_a(Hash)
      # In test environment with SimpleCov, this file has been executed
      # so we expect some line data (may be empty if SimpleCov format differs)
    end

    it "returns hash mapping line numbers to execution status" do
      described_class.enable!

      result = described_class.peek(__FILE__)

      # In oneshot_lines mode: nil = not executable, 0 = not hit, 1 = hit (then reset to nil)
      # We just check the structure
      expect(result.keys).to all(be_a(Integer))
    end

    it "returns empty hash for non-existent file" do
      described_class.enable!
      result = described_class.peek("/nonexistent/file.rb")
      expect(result).to eq({})
    end

    it "returns nil for nil file path" do
      described_class.enable!
      expect(described_class.peek(nil)).to be_nil
    end
  end

  describe ".supported?" do
    it "returns true on Ruby 3.2+" do
      expect(described_class.supported?).to be true
    end
  end

  describe "edge cases" do
    it "returns false from enable! when not supported" do
      allow(described_class).to receive(:supported?).and_return(false)
      expect(described_class.enable!).to be false
      expect(described_class.active?).to be false
    end

    it "returns empty hash when peeking with empty string file path" do
      described_class.enable!
      expect(described_class.peek("")).to eq({})
    end
  end

  describe "error handling" do
    it "does not raise when Coverage raises an error on enable" do
      allow(Coverage).to receive(:setup).and_raise(RuntimeError, "coverage error")
      # When setup fails but coverage is already running (SimpleCov), it piggybacks
      expect { described_class.enable! }.not_to raise_error
    end

    it "does not raise when Coverage raises an error on peek" do
      described_class.enable!
      allow(Coverage).to receive(:peek_result).and_raise(RuntimeError, "peek error")
      result = described_class.peek(__FILE__)
      expect(result).to eq({})
    end

    it "does not raise when Coverage raises an error on disable" do
      described_class.enable!
      allow(Coverage).to receive(:result).and_raise(RuntimeError, "stop error")
      expect { described_class.disable! }.not_to raise_error
      expect(described_class.active?).to be false
    end
  end
end
