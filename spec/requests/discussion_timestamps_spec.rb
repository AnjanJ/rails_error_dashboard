# frozen_string_literal: true

require "rails_helper"

# Timestamps in the discussion card: the audit trail's own comments, and the
# comments fetched from a linked issue tracker.
RSpec.describe "Discussion timestamps", type: :request do
  let!(:application) { create(:application) }
  let(:error) { create(:error_log, application: application) }
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    forgery = ActionController::Base.allow_forgery_protection
    tracking = config.enable_issue_tracking
    config.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
    Rails.cache.clear
    example.run
  ensure
    config.authenticate_with = nil
    config.enable_issue_tracking = tracking
    ActionController::Base.allow_forgery_protection = forgery
    Rails.cache.clear
  end

  describe "audit trail comments" do
    before do
      error.comments.create!(author_name: "gandalf", body: "looking into it", created_at: Time.utc(2026, 3, 9, 14, 5))
    end

    it "renders the time through local_time, in the viewer's format" do
      get "/error_dashboard/errors/#{error.id}"

      stamp = Nokogiri::HTML(response.body).at_css("#section-discussion .local-time")
      expect(stamp).to be_present
      expect(stamp["data-utc"]).to eq("2026-03-09T14:05:00Z")
      expect(stamp["data-format"]).to eq(I18n.t("red.time.formats.datetime"))
      # The hardcoded US pattern: "Mar 09, 2026 at 02:05 PM".
      expect(response.body).not_to include("2026 at 02:05 PM")
    end

    it "uses the locale's own date ordering" do
      post "/error_dashboard/locale", params: { locale: "de" }

      get "/error_dashboard/errors/#{error.id}"

      stamp = Nokogiri::HTML(response.body).at_css("#section-discussion .local-time")
      expect(stamp["data-format"]).to eq("%d. %b %Y %H:%M")
    end
  end
end
