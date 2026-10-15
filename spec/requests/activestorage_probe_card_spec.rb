# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActiveStorage Health page reachability card", type: :request do
  let!(:application) { create(:application) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    RailsErrorDashboard.configuration.enable_breadcrumbs = true
    RailsErrorDashboard.configuration.enable_activestorage_tracking = true
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "shows no card when no storage service is configured" do
    allow_any_instance_of(RailsErrorDashboard::Services::ActiveStorageProbe).to receive(:configured?).and_return(false)

    get "/error_dashboard/errors/activestorage_health_summary"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Service reachability")
  end

  it "shows the service as reachable with its latency" do
    service = instance_double("ActiveStorage::Service::DiskService", name: "local", exist?: false)
    allow_any_instance_of(RailsErrorDashboard::Services::ActiveStorageProbe).to receive(:storage_service).and_return(service)

    get "/error_dashboard/errors/activestorage_health_summary"

    expect(response.body).to include("Service reachability", "Reachable", "Service: local", "ms round trip")
    expect(response.body).not_to include("Unreachable")
  end

  it "shows the service as unreachable with the exception class" do
    service = instance_double("ActiveStorage::Service::S3Service", name: "amazon")
    allow(service).to receive(:exist?).and_raise(Errno::ECONNREFUSED)
    allow_any_instance_of(RailsErrorDashboard::Services::ActiveStorageProbe).to receive(:storage_service).and_return(service)

    get "/error_dashboard/errors/activestorage_health_summary"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Unreachable", "Errno::ECONNREFUSED", "Service: amazon")
  end
end
