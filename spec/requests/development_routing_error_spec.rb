# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# Does development record a mistyped URL that production doesn't? A real app is
# booted each way, because the suite's own app is already booted with neither
# set of settings. The dummy app ignores RoutingError, so that goes too, or this
# would prove nothing. The route that really raises is the control: without it,
# "nothing recorded" could just mean capture was off.
RSpec.describe "A request for an unknown URL" do
  script = <<~'RUBY'
    root = ARGV.fetch(0)
    reloading = ARGV.fetch(1) == "reloading"
    ENV["RAILS_ENV"] = "test"
    require File.join(root, "spec/dummy/config/application")

    config = Rails.application.config
    config.cache_classes = !reloading
    config.eager_load = !reloading
    config.consider_all_requests_local = reloading
    config.action_dispatch.show_exceptions = Rails.gem_version >= Gem::Version.new("7.1") ? :all : true
    config.logger = ActiveSupport::Logger.new(File::NULL)

    Rails.application.initialize!
    ActiveRecord::Migration.suppress_messages { load File.join(root, "spec/dummy/db/schema.rb") }
    RailsErrorDashboard.configuration.ignored_exceptions = []
    Rails.application.routes.append { get "/red_control_boom", to: ->(_env) { raise "control" } }
    Rails.application.reload_routes!

    client = Rack::MockRequest.new(Rails.application)
    missing = client.get("/no/such/page").status
    after_missing = RailsErrorDashboard::ErrorLog.count
    control = client.get("/red_control_boom").status
    puts "RESULT #{{ missing: missing, after_missing: after_missing, control: control, after_control: RailsErrorDashboard::ErrorLog.count }.to_json}"
  RUBY

  define_method(:request_it) do |mode|
    Dir.mktmpdir("red_routing") do |dir|
      env = { "DATABASE_URL" => "sqlite3:#{File.join(dir, 'app.sqlite3')}", "RED_TEST_SCHEMA" => nil }
      out, status = Open3.capture2e(env, Gem.ruby, "-e", script, RailsErrorDashboard::Engine.root.to_s, mode)
      raise "the app didn't run:\n#{out}" unless status.success? && out.include?("RESULT ")

      JSON.parse(out[/^RESULT (.*)$/, 1])
    end
  end

  it "isn't recorded with code reloading on, as in development (small-fixes-0-18/REQ-4)" do
    expect(request_it("reloading")).to include("missing" => 404, "after_missing" => 0)
  end

  it "isn't recorded with production's settings (small-fixes-0-18/REQ-4)" do
    expect(request_it("eager")).to include("missing" => 404, "after_missing" => 0)
  end

  it "does record an exception that really happens, so that zero means something (small-fixes-0-18/REQ-4)" do
    expect(request_it("eager")).to include("control" => 500, "after_control" => 1)
    expect(request_it("reloading")).to include("control" => 500, "after_control" => 1)
  end
end
