# frozen_string_literal: true

require "rails_helper"

# In an API-only host the dashboard brings its own cookies and session, on the
# engine's middleware stack only. It must leave a session the host runs itself
# alone, and must not mistake Rails' disabled placeholder for one.
RSpec.describe RailsErrorDashboard::Middleware::DashboardSession do
  let(:seen) { {} }
  let(:dashboard) do
    lambda do |env|
      request = ActionDispatch::Request.new(env)
      seen[:session] = request.session
      seen[:flash] = request.flash
      request.session[:visited] = "yes"
      [ 200, { "content-type" => "text/plain" }, [ "ok" ] ]
    end
  end
  let(:middleware) { described_class.new(dashboard) }

  # The cookie jar needs the app's key generator and cookie settings.
  def env_for(path = "/red/errors")
    Rails.application.env_config.merge(Rack::MockRequest.env_for(path))
  end

  def set_cookie(headers)
    Array(headers["set-cookie"] || headers["Set-Cookie"]).join("\n")
  end

  # host-hygiene-0-17/REQ-2 and REQ-4
  it "gives a request with no session a working one, under the dashboard's own cookie" do
    _status, headers, _body = middleware.call(env_for)

    expect(set_cookie(headers)).to include("_rails_error_dashboard_session=")
    expect(seen[:session][:visited]).to eq("yes")
    expect(seen[:flash]).to be_a(ActionDispatch::Flash::FlashHash)
  end

  # host-hygiene-0-17/REQ-2: the session survives to the next request.
  it "reads back what the previous request stored" do
    _status, headers, _body = middleware.call(env_for)
    cookie = set_cookie(headers)[/_rails_error_dashboard_session=[^;]+/]

    middleware.call(env_for.merge("HTTP_COOKIE" => cookie))

    expect(seen[:session][:visited]).to eq("yes")
  end

  # host-hygiene-0-17/REQ-3
  it "uses a session the host runs itself, and sets no cookie of its own" do
    host_stack = ActionDispatch::Cookies.new(
      ActionDispatch::Session::CookieStore.new(middleware, key: "_host_app_session")
    )

    _status, headers, _body = host_stack.call(env_for)

    expect(set_cookie(headers)).to include("_host_app_session=")
    expect(set_cookie(headers)).not_to include("_rails_error_dashboard_session")
    expect(seen[:session][:visited]).to eq("yes")
  end

  # host-hygiene-0-17/REQ-2: Rails stores a disabled placeholder on any earlier
  # session read when no session middleware ran. That is not a host session.
  it "gives a request carrying only Rails' disabled placeholder a working session" do
    skip "this Rails has no disabled session placeholder" unless ActionDispatch::Request::Session.respond_to?(:disabled)

    env = env_for
    ActionDispatch::Request.new(env).session # the earlier read
    expect(env["rack.session"]).not_to be_enabled

    _status, headers, _body = middleware.call(env)

    expect(set_cookie(headers)).to include("_rails_error_dashboard_session=")
    expect(seen[:session][:visited]).to eq("yes")
  end
end
