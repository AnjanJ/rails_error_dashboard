# frozen_string_literal: true

require "rails_helper"

# When Solid Queue runs RED's jobs with a config/queue.yml that would never run
# them (no dispatcher, no worker for RED's queues), every dashboard page says so.
RSpec.describe "Solid Queue config banner", type: :request do
  let!(:application) { create(:application) }
  let(:check) { RailsErrorDashboard::Services::SolidQueueConfigCheck }

  before { RailsErrorDashboard.configuration.authenticate_with = -> { true } }

  it "warns, with each problem, when Solid Queue would never run RED's jobs" do
    allow(check).to receive(:current_problems).and_return([ "test: workers but no dispatcher" ])

    get "/error_dashboard/errors"

    expect(response.body).to include('id="solid-queue-warning"', "test: workers but no dispatcher")
  end

  it "shows nothing when the config is fine" do
    allow(check).to receive(:current_problems).and_return([])

    get "/error_dashboard/errors"

    expect(response.body).not_to include('id="solid-queue-warning"')
  end
end
