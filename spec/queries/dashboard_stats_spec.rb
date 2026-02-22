# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::DashboardStats do
  let(:app) { create(:application) }

  describe ".call" do
    it "returns reopened count" do
      create(:error_log, application: app)
      create(:error_log, :reopened, application: app)
      create(:error_log, :reopened, application: app)

      stats = described_class.call(application_id: app.id)

      expect(stats[:reopened]).to eq(2)
    end

    it "returns zero when no errors are reopened" do
      create(:error_log, application: app)

      stats = described_class.call(application_id: app.id)

      expect(stats[:reopened]).to eq(0)
    end

    it "scopes reopened count to the given application" do
      other_app = create(:application)
      create(:error_log, :reopened, application: app)
      create(:error_log, :reopened, application: other_app)

      stats = described_class.call(application_id: app.id)

      expect(stats[:reopened]).to eq(1)
    end
  end
end
