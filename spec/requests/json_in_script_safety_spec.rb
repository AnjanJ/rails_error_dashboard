# frozen_string_literal: true

require "rails_helper"

# Companion to spec/views/no_raw_json_in_views_spec.rb (the static guard).
# ActiveSupport.escape_html_entities_in_json belongs to the host app. With it
# off, #to_json leaves "</script>" intact, and a captured value that contains
# it closes the chart script and is parsed as HTML. js_safe_json does not
# depend on the setting.
RSpec.describe "JSON inlined into script blocks, with escape_html_entities_in_json off", type: :request do
  let!(:application) { create(:application) }

  around do |example|
    was = ActiveSupport.escape_html_entities_in_json
    auth = RailsErrorDashboard.configuration.authenticate_with
    comparison = RailsErrorDashboard.configuration.enable_platform_comparison
    RailsErrorDashboard.configuration.enable_platform_comparison = true
    ActiveSupport.escape_html_entities_in_json = false
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    Rails.cache.clear
    begin
      example.run
    ensure
      ActiveSupport.escape_html_entities_in_json = was
      RailsErrorDashboard.configuration.authenticate_with = auth
      RailsErrorDashboard.configuration.enable_platform_comparison = comparison
      Rails.cache.clear
    end
  end

  let(:payload) { "</script><script>window.pwn=1</script>" }

  it "does not let an error type close the analytics chart script" do
    create(:error_log, application: application, error_type: "Evil#{payload}", occurred_at: 1.hour.ago)

    get "/error_dashboard/errors/analytics"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(payload)
  end

  it "does not let a platform name close the platform comparison script" do
    create(:error_log, application: application, platform: "ios#{payload}", occurred_at: 1.hour.ago)

    get "/error_dashboard/errors/platform_comparison"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(payload)
  end
end
