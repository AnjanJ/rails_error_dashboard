# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ActiveStorageProbe do
  # The dummy app configures a Disk service (spec/dummy/config/storage.yml);
  # these examples swap in a double so the transport can be made to fail.
  let(:service) { instance_double("ActiveStorage::Service::DiskService", name: "local") }

  # The double stands in for the real service through the probe's own seam.
  before { allow_any_instance_of(described_class).to receive(:storage_service).and_return(service) }

  it "reports ok with the service name and latency when the existence check returns" do
    allow(service).to receive(:exist?).with(described_class::PROBE_KEY).and_return(false)

    result = described_class.call

    expect(result).to include(status: "ok", service: "local")
    expect(result[:latency_ms]).to be_a(Numeric)
  end

  it "treats a key that somehow exists as reachable too: the round trip is the test" do
    allow(service).to receive(:exist?).and_return(true)

    expect(described_class.call[:status]).to eq("ok")
  end

  it "reports down with the exception class only, never the message" do
    allow(service).to receive(:exist?).and_raise(Errno::ECONNREFUSED, "s3.internal-bucket.example:443")

    result = described_class.call

    expect(result).to eq(status: "down", service: "local", error: "Errno::ECONNREFUSED")
    expect(result.to_json).not_to include("internal-bucket")
  end

  it "falls back to the class name when the service has no configured name" do
    stub_const("ActiveStorage::Service::FakeService", Class.new {
      def name = nil
      def exist?(_key) = false
    })
    allow_any_instance_of(described_class).to receive(:storage_service).and_return(ActiveStorage::Service::FakeService.new)

    expect(described_class.call[:service]).to eq("fake")
  end

  it "skips when the app never configured a storage service, without loading Blob" do
    allow_any_instance_of(described_class).to receive(:configured?).and_return(false)
    expect_any_instance_of(described_class).not_to receive(:storage_service)

    expect(described_class.call).to eq(status: "skipped", reason: "no_service_configured")
  end

  it "skips when a service is named but resolves to nothing" do
    allow_any_instance_of(described_class).to receive(:storage_service).and_return(nil)

    expect(described_class.call).to eq(status: "skipped", reason: "no_service_configured")
  end

  it "skips when ActiveStorage is not loaded" do
    hide_const("ActiveStorage")

    expect(described_class.call).to eq(status: "skipped", reason: "active_storage_not_loaded")
  end


  it "never raises, even when reading the service itself fails" do
    allow_any_instance_of(described_class).to receive(:storage_service).and_raise(RuntimeError, "boom")

    expect { described_class.call }.not_to raise_error
    expect(described_class.call[:status]).to eq("down")
  end

  describe "against the dummy app's real Disk service" do
    # Undo the outer stub: this one goes through ActiveStorage::Blob.service.
    before { allow_any_instance_of(described_class).to receive(:storage_service).and_call_original }

    it "reports ok with the configured name" do
      expect(described_class.call).to include(status: "ok", service: "test")
    end
  end
end
