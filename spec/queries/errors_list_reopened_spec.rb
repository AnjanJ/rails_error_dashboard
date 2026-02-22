# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::ErrorsList, "reopened filter" do
  let(:app) { create(:application) }

  describe "filter_by_reopened" do
    let!(:normal_error) { create(:error_log, application: app) }
    let!(:reopened_error) { create(:error_log, :reopened, application: app) }

    it "returns only reopened errors when reopened filter is true" do
      results = described_class.call(reopened: "true")

      expect(results).to include(reopened_error)
      expect(results).not_to include(normal_error)
    end

    it "returns all errors when reopened filter is not set" do
      results = described_class.call({})

      expect(results).to include(normal_error)
      expect(results).to include(reopened_error)
    end

    it "ignores reopened filter when value is not 'true'" do
      results = described_class.call(reopened: "false")

      expect(results).to include(normal_error)
      expect(results).to include(reopened_error)
    end
  end
end
