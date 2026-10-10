# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Queries::HealthStatus do
  subject(:result) { described_class.call }

  after { RailsErrorDashboard.reset_configuration! }

  describe "when everything answers" do
    it "reports ok with the gem version and a timestamp" do
      expect(result[:status]).to eq("ok")
      expect(result[:version]).to eq(RailsErrorDashboard::VERSION)
      expect(result[:timestamp]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      expect(result[:duration_ms]).to be_a(Numeric)
    end

    it "probes the error database and names its adapter" do
      db = result[:checks][:database]
      expect(db[:status]).to eq("ok")
      expect(db[:adapter]).to be_present
      expect(db[:tables_present]).to be(true)
      expect(db[:separate_database]).to be(false)
      expect(db[:latency_ms]).to be_a(Numeric)
    end

    it "reports the last capture and the last-24h count" do
      create(:error_log, occurred_at: 2.hours.ago)
      create(:error_log, occurred_at: 3.days.ago)

      errors = result[:checks][:errors]
      expect(errors[:status]).to eq("ok")
      expect(errors[:last_24h]).to eq(1)
      expect(Time.iso8601(errors[:last_error_at])).to be_within(2.seconds).of(2.hours.ago)
    end

    it "reports null last_error_at on an empty table" do
      expect(result[:checks][:errors][:last_error_at]).to be_nil
      expect(result[:checks][:errors][:last_24h]).to eq(0)
    end

    it "reports the queue adapter and the async flag" do
      queue = result[:checks][:queue]
      expect(queue[:status]).to eq("ok")
      expect(queue[:adapter]).to eq("test")
      expect(queue[:async_logging]).to be(false)
      expect(queue[:problems]).to eq([])
    end

    it "reports storm protection as closed when it is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false

      storm = result[:checks][:storm_protection]
      expect(storm).to eq(status: "ok", enabled: false, state: "closed")
    end
  end

  describe "when the error database is unreachable" do
    before do
      allow(RailsErrorDashboard::ErrorLogsRecord).to receive(:connection_pool)
        .and_raise(ActiveRecord::ConnectionNotEstablished, "postgres://secret-host:5432 refused")
    end

    it "reports down without raising and without leaking the message" do
      expect(result[:status]).to eq("down")
      expect(result[:checks][:database][:status]).to eq("down")
      expect(result[:checks][:database][:error]).to eq("ActiveRecord::ConnectionNotEstablished")
      expect(result.to_json).not_to include("secret-host")
    end

    it "skips the error queries rather than running them against a dead server" do
      expect(RailsErrorDashboard::ErrorLog).not_to receive(:maximum)
      expect(result[:checks][:errors]).to include(status: "degraded", skipped: "database unreachable")
    end

    it "maps down to HTTP 503" do
      expect(described_class.http_status_for(result)).to eq(503)
    end
  end

  describe "when RED's tables are missing" do
    before { allow(RailsErrorDashboard::ErrorLog).to receive(:table_exists?).and_return(false) }

    it "reports down with the reason" do
      expect(result[:status]).to eq("down")
      expect(result[:checks][:database]).to include(status: "down", tables_present: false, reason: "missing_tables")
    end
  end

  describe "when a storm is in progress" do
    before do
      RailsErrorDashboard.configuration.enable_storm_protection = true
      allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:state).and_return(:shedding)
    end

    it "is degraded, not down, and still HTTP 200" do
      expect(result[:status]).to eq("degraded")
      expect(result[:checks][:storm_protection]).to eq(status: "degraded", enabled: true, state: "shedding")
      expect(described_class.http_status_for(result)).to eq(200)
    end
  end

  describe "when Solid Queue would not run RED's jobs" do
    before do
      allow(RailsErrorDashboard::Services::SolidQueueConfigCheck).to receive(:current_problems)
        .and_return([ "production: no worker serves the default queue" ])
    end

    it "is degraded and lists the problems" do
      expect(result[:status]).to eq("degraded")
      expect(result[:checks][:queue][:status]).to eq("degraded")
      expect(result[:checks][:queue][:problems]).to eq([ "production: no worker serves the default queue" ])
    end
  end

  describe "when one probe raises unexpectedly" do
    before { allow(RailsErrorDashboard::ErrorLog).to receive(:maximum).and_raise(NoMethodError, "boom") }

    it "degrades that check and keeps the others" do
      expect(result[:status]).to eq("degraded")
      expect(result[:checks][:errors]).to eq(status: "degraded", error: "NoMethodError")
      expect(result[:checks][:database][:status]).to eq("ok")
    end
  end

  describe "active storage" do
    it "is skipped, and neutral for the overall answer, when no service is configured" do
      allow_any_instance_of(RailsErrorDashboard::Services::ActiveStorageProbe).to receive(:configured?).and_return(false)

      expect(result[:status]).to eq("ok")
      expect(result[:checks][:active_storage]).to eq(status: "skipped", reason: "no_service_configured")
    end

    it "reports the service and latency when the probe answers" do
      service = instance_double("ActiveStorage::Service::DiskService", name: "local", exist?: false)
      allow_any_instance_of(RailsErrorDashboard::Services::ActiveStorageProbe).to receive(:storage_service).and_return(service)

      check = result[:checks][:active_storage]
      expect(check).to include(status: "ok", service: "local")
      expect(check[:latency_ms]).to be_a(Numeric)
    end

    it "degrades, never downs, the overall answer when the service is unreachable" do
      service = instance_double("ActiveStorage::Service::S3Service", name: "amazon")
      allow(service).to receive(:exist?).and_raise(SocketError, "getaddrinfo")
      allow_any_instance_of(RailsErrorDashboard::Services::ActiveStorageProbe).to receive(:storage_service).and_return(service)

      expect(result[:status]).to eq("degraded")
      expect(result[:checks][:active_storage]).to eq(status: "degraded", service: "amazon", error: "SocketError")
      expect(described_class.http_status_for(result)).to eq(200)
    end
  end

  it "honours use_separate_database in the report" do
    RailsErrorDashboard.configuration.use_separate_database = true

    expect(result[:checks][:database][:separate_database]).to be(true)
  end
end
