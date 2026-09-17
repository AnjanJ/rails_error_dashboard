# frozen_string_literal: true

require "rails_helper"

# Found by re-running the hostile route sweep against the hardened branches.
# Three things could still take a page down: a row holding invalid bytes that
# was written before capture started scrubbing them, a `days` parameter that
# arrives as a Hash, and an `application_id` that arrives as an Array.
RSpec.describe "Hostile input that used to take a page down", type: :request do
  let!(:application) { create(:application) }
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    auth = config.authenticate_with
    comparison = config.enable_platform_comparison
    config.authenticate_with = -> { true }
    config.enable_platform_comparison = true
    Rails.cache.clear
    begin
      example.run
    ensure
      config.authenticate_with = auth
      config.enable_platform_comparison = comparison
      Rails.cache.clear
    end
  end

  describe "a row that holds invalid bytes (written before 0.13.0 on SQLite/MySQL)" do
    let(:legacy) { create(:error_log, application: application, error_type: "BinaryError", occurred_at: 1.hour.ago) }

    before do
      skip "raw invalid bytes can only be stored on SQLite" unless RailsErrorDashboard::ErrorLog.connection.adapter_name.match?(/sqlite/i)

      table = RailsErrorDashboard::ErrorLog.table_name
      RailsErrorDashboard::ErrorLog.connection.execute(
        "UPDATE #{table} SET message = CAST(X'6361FFFE20C328' AS TEXT), backtrace = CAST(X'FF0041' AS TEXT), " \
        "user_agent = CAST(X'41FF' AS TEXT) WHERE id = #{legacy.id}"
      )
    end

    it "is read back as valid UTF-8, without writing anything" do
      row = RailsErrorDashboard::ErrorLog.find(legacy.id)

      expect(row.message).to be_valid_encoding
      expect(row.backtrace).to be_valid_encoding
      expect(row.user_agent).to be_valid_encoding
      expect(row).not_to be_changed
    end

    %w[/errors /overview /errors/platform_comparison /errors/analytics].each do |path|
      it "does not take #{path} down" do
        get "/error_dashboard#{path}", params: { unresolved: "0", per_page: "100" }

        expect(response).to have_http_status(:ok)
      end
    end

    it "does not take its own page down" do
      get "/error_dashboard/errors/#{legacy.id}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "a days parameter that is not a scalar" do
    %w[analytics correlation deprecations releases user_impact platform_comparison].each do |page|
      it "falls back to the default on /errors/#{page}" do
        get "/error_dashboard/errors/#{page}", params: { days: { x: "1" } }
        expect(response.status).to be < 500

        get "/error_dashboard/errors/#{page}", params: { days: [ "7" ] }
        expect(response.status).to be < 500
      end
    end
  end

  describe "an application_id that arrives as an Array" do
    %w[/overview /errors /errors/analytics /errors/platform_comparison].each do |path|
      it "does not take #{path} down" do
        get "/error_dashboard#{path}", params: { application_id: [ application.id.to_s ] }

        expect(response.status).to be < 500
      end
    end
  end
end
