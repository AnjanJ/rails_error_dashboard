# frozen_string_literal: true

require "rails_helper"

# docs/guides/CONFIGURATION.md "Custom Grouping" and the FEATURES.md example say
# what a custom_fingerprint lambda receives. The FEATURES example once read
# context[:controller], a key that is never there, so every RecordNotFound fell
# into one group and nothing said why.
RSpec.describe "custom_fingerprint context" do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved = [ config.async_logging, config.custom_fingerprint ]
    config.async_logging = false
    example.run
  ensure
    config.async_logging, config.custom_fingerprint = saved
  end

  # What a controller's Rails.error.report sees: RED's middleware leaves the
  # Rack env for the subscriber, routing parameters included.
  def report_in_request(path, controller:, action:, message:)
    Thread.current[:rails_error_dashboard_request_env] = Rack::MockRequest.env_for(
      "https://example.com#{path}",
      "action_dispatch.request.path_parameters" => { controller: controller, action: action }
    )
    raise ActiveRecord::RecordNotFound, message
  rescue ActiveRecord::RecordNotFound => e
    Rails.error.report(e, handled: true, severity: :error)
  ensure
    Thread.current[:rails_error_dashboard_request_env] = nil
  end

  def groups
    RailsErrorDashboard::ErrorLog.where(error_type: "ActiveRecord::RecordNotFound")
      .order(:id).pluck(:occurrence_count)
  end

  it "receives the flat capture context, not the request or the controller" do
    seen = nil
    config.custom_fingerprint = ->(_exception, context) { seen ||= context; nil }

    report_in_request("/players/42?tab=stats", controller: "players", action: "show",
                      message: "Couldn't find Player with 'id'=42")

    expect(seen).to include(request_url: "/players/42?tab=stats", controller_name: "players", action_name: "show")
    expect(seen).not_to have_key(:request)
    expect(seen).not_to have_key(:controller)
  end

  it "groups by controller with the FEATURES.md example" do
    config.custom_fingerprint = ->(exception, context) {
      "record-not-found-#{context[:controller_name]}" if exception.is_a?(ActiveRecord::RecordNotFound)
    }

    report_in_request("/players/1", controller: "players", action: "show", message: "Couldn't find Player with 'id'=1")
    report_in_request("/players/2", controller: "players", action: "edit", message: "Couldn't find Player with 'id'=2")
    report_in_request("/teams/3", controller: "teams", action: "show", message: "Couldn't find Team with 'id'=3")

    expect(groups).to eq([ 2, 1 ])
  end

  it "groups by path, IDs collapsed, with the CONFIGURATION.md example" do
    config.custom_fingerprint = ->(exception, context) {
      case exception
      when ActiveRecord::RecordNotFound
        path = context[:request_url]&.split("?")&.first
        "404:#{path.gsub(/\d+/, ':id')}" if path
      end
    }

    report_in_request("/players/1", controller: "players", action: "show", message: "Couldn't find Player with 'id'=1")
    report_in_request("/players/2?tab=stats", controller: "players", action: "show", message: "Couldn't find Player with 'id'=2")
    report_in_request("/players/2/games", controller: "games", action: "index", message: "Couldn't find Player with 'id'=2")

    expect(groups).to eq([ 2, 1 ])

    begin
      raise ActiveRecord::RecordNotFound, "Couldn't find Player with 'id'=9"
    rescue ActiveRecord::RecordNotFound => e
      Rails.error.report(e, handled: true, severity: :error) # no request: a job, a script
    end
    expect(groups).to eq([ 2, 1, 1 ])
  end
end
