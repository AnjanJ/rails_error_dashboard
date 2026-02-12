# frozen_string_literal: true

# ============================================================================
# Full Integration Test Runner
# CSRF-aware HTTP test framework for comprehensive dashboard testing
# Used by: bin/full-integration-test
#
# Runs OUTSIDE Rails (plain Ruby with Net::HTTP) — no Rails dependencies.
# Tests the gem as a real user would: via HTTP requests with basic auth.
# ============================================================================

require "net/http"
require "uri"
require "json"
require "cgi"

module IntegrationTestRunner
  PASS_COUNT = [ 0 ]
  FAIL_COUNT = [ 0 ]

  # Session state: cookies + CSRF token
  @cookies = {}
  @csrf_token = nil
  @base_url = nil
  @auth_user = nil
  @auth_pass = nil

  class << self
    attr_accessor :cookies, :csrf_token, :base_url, :auth_user, :auth_pass

    def configure(base_url:, user:, password:)
      @base_url = base_url
      @auth_user = user
      @auth_pass = password
      @cookies = {}
      @csrf_token = nil
    end

    def reset!
      PASS_COUNT[0] = 0
      FAIL_COUNT[0] = 0
      @cookies = {}
      @csrf_token = nil
    end

    def passed = PASS_COUNT[0]
    def failed = FAIL_COUNT[0]

    # --- Assertions ---

    def assert(label, condition, detail = nil)
      if condition
        $stdout.puts "  \u2713 #{label}"
        PASS_COUNT[0] += 1
      else
        $stdout.puts "  \u2717 FAIL: #{label}#{detail ? " -- #{detail}" : ""}"
        FAIL_COUNT[0] += 1
      end
    end

    def assert_status(label, response, expected_range = 200..399)
      code = response.code.to_i
      if expected_range.include?(code)
        $stdout.puts "  \u2713 #{label} -> #{code}"
        PASS_COUNT[0] += 1
      else
        $stdout.puts "  \u2717 FAIL: #{label} -> #{code} (expected #{expected_range})"
        FAIL_COUNT[0] += 1
      end
    end

    def assert_contains(label, body, *terms)
      missing = terms.reject { |t| body.include?(t) }
      if missing.empty?
        $stdout.puts "  \u2713 #{label}"
        PASS_COUNT[0] += 1
      else
        $stdout.puts "  \u2717 FAIL: #{label} -- missing: #{missing.join(", ")}"
        FAIL_COUNT[0] += 1
      end
    end

    def assert_not_contains(label, body, *terms)
      found = terms.select { |t| body.include?(t) }
      if found.empty?
        $stdout.puts "  \u2713 #{label}"
        PASS_COUNT[0] += 1
      else
        $stdout.puts "  \u2717 FAIL: #{label} -- unexpectedly found: #{found.join(", ")}"
        FAIL_COUNT[0] += 1
      end
    end

    # --- HTTP Helpers ---

    # GET with basic auth and cookie session (follows redirects)
    def get(path, params: {}, auth: true, max_redirects: 3)
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?

      req = Net::HTTP::Get.new(uri)
      req.basic_auth(@auth_user, @auth_pass) if auth
      apply_cookies(req)

      response = execute(uri, req)
      store_cookies(response)

      # Follow redirects
      redirects = 0
      while [ 301, 302, 303, 307 ].include?(response.code.to_i) && redirects < max_redirects
        redirect_path = response["Location"]
        break unless redirect_path
        redirect_path = redirect_path.sub(@base_url, "") if redirect_path.start_with?("http")
        uri = URI("#{@base_url}#{redirect_path}")
        req = Net::HTTP::Get.new(uri)
        req.basic_auth(@auth_user, @auth_pass) if auth
        apply_cookies(req)
        response = execute(uri, req)
        store_cookies(response)
        redirects += 1
      end

      extract_csrf_token(response.body) if response.code.to_i == 200
      response
    rescue => e
      $stdout.puts "  [HTTP ERROR] GET #{path}: #{e.class}: #{e.message}"
      nil
    end

    # POST with basic auth, CSRF token, and cookie session
    def post(path, params: {}, auth: true)
      # If we don't have a CSRF token yet, fetch one
      refresh_csrf_token if @csrf_token.nil?

      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Post.new(uri)
      req.basic_auth(@auth_user, @auth_pass) if auth
      req["Content-Type"] = "application/x-www-form-urlencoded"
      apply_cookies(req)

      # Add CSRF token to form params
      form_params = params.merge("authenticity_token" => @csrf_token || "")
      req.body = URI.encode_www_form(form_params)

      response = execute(uri, req)
      store_cookies(response)

      # Follow redirect if 302/303
      if [ 302, 303 ].include?(response.code.to_i)
        redirect_path = response["Location"]
        if redirect_path
          redirect_path = redirect_path.sub(@base_url, "") if redirect_path.start_with?("http")
          return get(redirect_path)
        end
      end

      response
    rescue => e
      $stdout.puts "  [HTTP ERROR] POST #{path}: #{e.class}: #{e.message}"
      nil
    end

    # GET without auth (for testing auth enforcement)
    def get_no_auth(path)
      get(path, auth: false)
    end

    # GET with wrong auth
    def get_wrong_auth(path)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth("wrong_user", "wrong_pass")

      response = execute(uri, req)
      response
    rescue => e
      $stdout.puts "  [HTTP ERROR] GET (wrong auth) #{path}: #{e.class}: #{e.message}"
      nil
    end

    # --- Output ---

    def section(title)
      puts ""
      puts "--- #{title} ---"
    end

    def header(title)
      puts ""
      puts "=" * 70
      puts title
      puts "=" * 70
      puts ""
    end

    def summary(phase_name)
      puts ""
      puts "=" * 70
      puts "#{phase_name} RESULTS: #{PASS_COUNT[0]} passed, #{FAIL_COUNT[0]} failed"
      puts "=" * 70
      FAIL_COUNT[0] > 0 ? 1 : 0
    end

    private

    def execute(uri, req)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 30
      http.request(req)
    end

    def apply_cookies(req)
      return if @cookies.empty?
      req["Cookie"] = @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
    end

    def store_cookies(response)
      return unless response

      Array(response.get_fields("Set-Cookie")).each do |cookie_str|
        name_value = cookie_str.split(";").first
        name, value = name_value.split("=", 2)
        @cookies[name.strip] = value&.strip || ""
      end
    end

    def extract_csrf_token(body)
      return unless body
      match = body.match(/name="csrf-token"\s+content="([^"]*)"/)
      match ||= body.match(/content="([^"]*)"\s+name="csrf-token"/)
      @csrf_token = match[1] if match
    end

    def refresh_csrf_token
      # Fetch overview page to get a CSRF token
      get("/")
    end
  end
end

# Convenience aliases
def assert(label, condition, detail = nil)
  IntegrationTestRunner.assert(label, condition, detail)
end

def assert_status(label, response, expected_range = 200..399)
  IntegrationTestRunner.assert_status(label, response, expected_range)
end

def assert_contains(label, body, *terms)
  IntegrationTestRunner.assert_contains(label, body, *terms)
end

def assert_not_contains(label, body, *terms)
  IntegrationTestRunner.assert_not_contains(label, body, *terms)
end

def get(path, params: {}, auth: true)
  IntegrationTestRunner.get(path, params: params, auth: auth)
end

def post(path, params: {}, auth: true)
  IntegrationTestRunner.post(path, params: params, auth: auth)
end

def get_no_auth(path)
  IntegrationTestRunner.get_no_auth(path)
end

def get_wrong_auth(path)
  IntegrationTestRunner.get_wrong_auth(path)
end

def section(title)
  IntegrationTestRunner.section(title)
end
