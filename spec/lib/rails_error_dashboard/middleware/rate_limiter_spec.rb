# frozen_string_literal: true

require "rails_helper"

# rate_limit_per_minute used to be validated and shown on the Settings page but
# never read: the limiter hardcoded 300 requests per minute.
RSpec.describe RailsErrorDashboard::Middleware::RateLimiter do
  let(:app) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] } }
  let(:middleware) { described_class.new(app) }
  let(:mount) { RailsErrorDashboard.configuration.engine_mount_path }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    RailsErrorDashboard.configuration.enable_rate_limiting = true
  end

  after { RailsErrorDashboard.reset_configuration! }

  def get(path, ip: "203.0.113.7")
    middleware.call(Rack::MockRequest.env_for(path, "REMOTE_ADDR" => ip))
  end

  it "defaults rate_limit_per_minute to 300" do
    expect(RailsErrorDashboard::Configuration.new.rate_limit_per_minute).to eq(300)
  end

  it "allows rate_limit_per_minute requests per IP and path, then answers 429" do
    RailsErrorDashboard.configuration.rate_limit_per_minute = 2

    expect(get("#{mount}/errors").first).to eq(200)
    expect(get("#{mount}/errors").first).to eq(200)
    status, headers, = get("#{mount}/errors")

    expect(status).to eq(429)
    expect(headers["X-RateLimit-Limit"]).to eq("2")
  end

  it "counts each IP and each path separately" do
    RailsErrorDashboard.configuration.rate_limit_per_minute = 1

    expect(get("#{mount}/errors").first).to eq(200)
    expect(get("#{mount}/errors", ip: "198.51.100.9").first).to eq(200)
    expect(get("#{mount}/overview").first).to eq(200)
    expect(get("#{mount}/errors").first).to eq(429)
  end

  it "falls back to 300 when rate_limit_per_minute is unset" do
    RailsErrorDashboard.configuration.rate_limit_per_minute = nil

    # A limit of 0 would refuse the very first request.
    expect(get("#{mount}/errors").first).to eq(200)
  end

  it "leaves the host app's own paths alone" do
    RailsErrorDashboard.configuration.rate_limit_per_minute = 1

    3.times { expect(get("/not-the-dashboard").first).to eq(200) }
  end

  # /red also matched /redirect: a host path that merely shares the mount's
  # first characters is not the dashboard.
  it "leaves a host path that shares the mount's prefix alone" do
    RailsErrorDashboard.configuration.rate_limit_per_minute = 1

    3.times { expect(get("#{mount}irect").first).to eq(200) }
    3.times { expect(get("#{mount}-archive/errors").first).to eq(200) }
  end

  it "still covers the mount itself and everything below it" do
    RailsErrorDashboard.configuration.rate_limit_per_minute = 1

    expect(get(mount).first).to eq(200)
    expect(get(mount).first).to eq(429)
    expect(get("#{mount}/").first).to eq(200)
    expect(get("#{mount}/").first).to eq(429)
  end

  it "does nothing unless enable_rate_limiting is on" do
    RailsErrorDashboard.configuration.enable_rate_limiting = false
    RailsErrorDashboard.configuration.rate_limit_per_minute = 1

    3.times { expect(get("#{mount}/errors").first).to eq(200) }
  end
end
