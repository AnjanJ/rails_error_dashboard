# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::CaptureLimits do
  # capture-hardening-0-17/REQ-1
  describe ".message" do
    it "keeps the first 10,000 characters and says how many were cut" do
      result = described_class.message("a" * 70_000)

      expect(result).to start_with("a" * 10_000)
      expect(result.delete_prefix("a" * 10_000)).to eq("… [60000 more characters]")
    end

    it "returns a message at the limit unchanged" do
      message = "b" * 10_000
      expect(described_class.message(message)).to equal(message)
    end

    it "counts characters, not bytes" do
      result = described_class.message("é" * 10_001)

      expect(result).to start_with("é" * 10_000)
      expect(result).to end_with("[1 more characters]")
    end

    it "passes nil and non-strings through" do
      expect(described_class.message(nil)).to be_nil
      expect(described_class.message(42)).to eq(42)
    end
  end

  # capture-hardening-0-17/REQ-2
  describe ".request_params" do
    let(:limit) { described_class::REQUEST_PARAMS_LIMIT }

    it "returns params under the limit unchanged" do
      params = { "a" => "b" }.to_json
      expect(described_class.request_params(params)).to equal(params)
    end

    it "drops the largest values first, keeps the small ones and the JSON valid" do
      params = { "upload" => "x" * 70_000, "note" => "y" * 10_000, "id" => "42", "name" => "Ada" }.to_json

      result = described_class.request_params(params)
      parsed = JSON.parse(result)

      expect(result.bytesize).to be <= limit
      expect(parsed).to include("id" => "42", "name" => "Ada", "note" => "y" * 10_000, "_truncated" => true)
      expect(parsed["upload"]).to eq("[TRUNCATED]")
    end

    it "keeps dropping until it fits when several values are large" do
      params = (1..10).to_h { |i| [ "field#{i}", "z" * 20_000 ] }.merge("id" => "7").to_json

      result = described_class.request_params(params)
      parsed = JSON.parse(result)

      expect(result.bytesize).to be <= limit
      expect(parsed["id"]).to eq("7")
      expect(parsed["_truncated"]).to be true
    end

    it "cuts text that is not a JSON object at a character boundary, with a marker" do
      result = described_class.request_params("é" * 40_000)

      expect(result.bytesize).to be <= limit
      expect(result).to be_valid_encoding
      expect(result).to end_with("[truncated]")
    end

    it "cuts a JSON array as text" do
      result = described_class.request_params(Array.new(20_000) { "abcd" }.to_json)

      expect(result.bytesize).to be <= limit
      expect(result).to end_with("[truncated]")
    end

    it "passes nil and non-strings through" do
      expect(described_class.request_params(nil)).to be_nil
      expect(described_class.request_params({ "a" => 1 })).to eq({ "a" => 1 })
    end
  end
end
