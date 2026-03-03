# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::CurlGenerator do
  def make_error(attrs = {})
    defaults = {
      http_method: "GET",
      hostname: "example.com",
      request_url: "/users",
      request_params: nil,
      content_type: nil,
      user_agent: nil
    }
    double("ErrorLog", defaults.merge(attrs))
  end

  describe ".call" do
    it "generates a GET curl command" do
      error = make_error(http_method: "GET", hostname: "example.com", request_url: "/users")
      result = described_class.call(error)

      expect(result).to include("curl")
      expect(result).to include("https://example.com/users")
      expect(result).not_to include("-X")
    end

    it "generates a POST curl with -X, body, and content type" do
      error = make_error(
        http_method: "POST",
        hostname: "example.com",
        request_url: "/users",
        request_params: '{"name":"test"}',
        content_type: "application/json"
      )
      result = described_class.call(error)

      expect(result).to include("curl")
      expect(result).to include("-X POST")
      expect(result).to include("https://example.com/users")
      expect(result).to include("-H 'Content-Type: application/json'")
      expect(result).to include('-d \'{"name":"test"}\'')
    end

    it "uses full URL when request_url is already absolute" do
      error = make_error(
        http_method: "GET",
        hostname: nil,
        request_url: "https://api.example.com/v1/users?page=2"
      )
      result = described_class.call(error)

      expect(result).to include("https://api.example.com/v1/users?page=2")
    end

    it "includes User-Agent when present" do
      error = make_error(user_agent: "Mozilla/5.0")
      result = described_class.call(error)

      expect(result).to include("-H 'User-Agent: Mozilla/5.0'")
    end

    it "uses http:// for localhost" do
      error = make_error(hostname: "localhost:3000", request_url: "/api")
      result = described_class.call(error)

      expect(result).to include("http://localhost:3000/api")
    end

    it "returns empty string when request_url is missing" do
      error = make_error(request_url: nil, hostname: nil)
      expect(described_class.call(error)).to eq("")
    end

    it "returns empty string when request_url is blank and hostname is missing" do
      error = make_error(request_url: "", hostname: nil)
      expect(described_class.call(error)).to eq("")
    end

    it "does not include -d for GET requests" do
      error = make_error(http_method: "GET", request_params: '{"page":"1"}')
      result = described_class.call(error)

      expect(result).not_to include("-d")
    end

    it "includes -d for PUT requests" do
      error = make_error(http_method: "PUT", request_params: '{"name":"updated"}')
      result = described_class.call(error)

      expect(result).to include("-X PUT")
      expect(result).to include("-d")
    end

    it "shell-quotes strings with single quotes" do
      error = make_error(
        http_method: "POST",
        request_url: "/test",
        hostname: "example.com",
        request_params: "it's a test"
      )
      result = described_class.call(error)

      expect(result).to include("it'\\''s a test")
    end

    it "returns empty string on nil input" do
      expect(described_class.call(nil)).to eq("")
    end

    it "returns empty string when error raises" do
      error = double("BrokenError")
      allow(error).to receive(:respond_to?).and_raise(RuntimeError, "boom")
      expect(described_class.call(error)).to eq("")
    end
  end
end
