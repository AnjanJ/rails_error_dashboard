# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Errors index filter pills", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    ActionController::Base.allow_forgery_protection = false
  end

  after do
    RailsErrorDashboard.configuration.authenticate_with = nil
    ActionController::Base.allow_forgery_protection = true
  end

  describe "priority_level pill" do
    # Regression: index.html.erb interpolated the raw integer ("P3" for level=3)
    # instead of looking up the short_label, inverting the P-number for users.
    # PRIORITY_LEVELS maps 3 → P0 (Critical), 2 → P1, 1 → P2, 0 → P3 (Low).
    it "shows P0 short_label when filtering by Critical (level=3)" do
      get "/error_dashboard/errors", params: { priority_level: 3 }
      expect(response.body).to include("Priority: P0")
      expect(response.body).not_to match(/Priority:\s*P3\b/)
    end

    it "shows P3 short_label when filtering by Low (level=0)" do
      get "/error_dashboard/errors", params: { priority_level: 0 }
      expect(response.body).to include("Priority: P3")
      expect(response.body).not_to match(/Priority:\s*P0\b/)
    end

    it "shows P? when priority_level is out of range" do
      get "/error_dashboard/errors", params: { priority_level: 99 }
      expect(response.body).to include("Priority: P?")
    end
  end
end
