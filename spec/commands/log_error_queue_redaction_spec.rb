# frozen_string_literal: true

require "rails_helper"

# Redaction at the QUEUE boundary, not just at the INSERT.
#
# Capture identity has to be computed from the RAW message -- redacting first
# would re-group every error whose message contains a filtered key -- but the
# async and storm paths compute it on the request thread and hand it to a
# worker over a queue. Shipping the raw message to do that put secrets in the
# queue's backing store (Redis, Solid Queue's tables), its backups and any
# job-argument logging, even though the ErrorLog row itself was redacted.
#
# The fingerprint is therefore two-stage: the request thread hashes the
# identity parts into an opaque digest, and only that digest travels. The
# worker adds application_id (which it can resolve, being allowed to touch the
# database) to get the canonical error_hash.
RSpec.describe "capture payload redaction at the queue boundary" do
  let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }
  let(:logs) { RailsErrorDashboard::ErrorLog }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.sampling_rate = 1.0
    config.filter_sensitive_data = true
    config.enable_storm_protection = false
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    gate.reset!
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::SensitiveDataFilter.reset!
    gate.reset!
  end

  def boom(message = "password=QUEUE_SECRET")
    error = StandardError.new(message)
    error.set_backtrace([ "#{Rails.root}/app/models/audit.rb:12:in 'run'" ])
    error
  end

  describe "the async queue" do
    before { RailsErrorDashboard.configuration.async_logging = true }

    it "carries neither the message secret nor the request params secret" do
      RailsErrorDashboard::Commands::LogError.call(
        boom, request_params: { token: "QUEUE_TOKEN" }.to_json
      )

      payload = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args).to_json

      expect(payload).not_to include("QUEUE_SECRET")
      expect(payload).not_to include("QUEUE_TOKEN")
    end

    it "carries the fingerprint as an opaque digest rather than message text" do
      RailsErrorDashboard::Commands::LogError.call(boom)

      _exception_data, context = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args)

      expect(context["_identity"]).to match(/\A[0-9a-f]{16}\z/)
    end

    # request_params is only ONE of the shapes that becomes the stored params.
    # ErrorContext#extract_params also folds in :params, :additional_context and
    # the job/sidekiq-derived keys, and those crossed the queue raw: the stored
    # row was filtered, so the leak was invisible from the dashboard while the
    # secret sat in Redis / Solid Queue, its backups and any job-argument log.
    it "redacts the raw params form the command also accepts" do
      RailsErrorDashboard::Commands::LogError.call(
        boom("plain failure"), params: { password: "QUEUE_RAW_PARAM" }
      )

      payload = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args).to_json

      expect(payload).not_to include("QUEUE_RAW_PARAM")
    end

    it "redacts additional_context, which mobile and API clients use" do
      RailsErrorDashboard::Commands::LogError.call(
        boom("plain failure"), additional_context: { api_key: "QUEUE_CTX_SECRET", screen: "Checkout" }
      )

      payload = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args).to_json

      expect(payload).not_to include("QUEUE_CTX_SECRET")
      # Benign context must survive -- this is investigation data.
      expect(payload).to include("Checkout")
    end

    it "redacts metadata supplied by a manual report" do
      RailsErrorDashboard::Commands::LogError.call(
        boom("plain failure"), metadata: { auth_token: "QUEUE_META_SECRET" }
      )

      payload = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args).to_json

      expect(payload).not_to include("QUEUE_META_SECRET")
    end

    it "still redacts the row itself when the job runs" do
      RailsErrorDashboard::Commands::LogError.call(
        boom, request_params: { token: "QUEUE_TOKEN" }.to_json
      )
      perform_enqueued_jobs

      row = logs.sole
      expect(row.message).to eq("password=[FILTERED]")
      expect(row.request_params.to_s).not_to include("QUEUE_TOKEN")
    end
  end

  # One capture, every boundary it can cross. Each sub-finding of the redaction
  # review was a single boundary drifting from the others; asserting them
  # together is what stops the next one drifting silently.
  describe "one policy at every boundary" do
    before { RailsErrorDashboard.configuration.async_logging = true }

    it "keeps the same secret out of the queue payload, the stored row and the span" do
      error = boom("auth failed password=OMNI_SECRET")

      RailsErrorDashboard::Commands::LogError.call(error, params: { api_key: "OMNI_PARAM" })

      # 1. the queue payload
      queue_payload = enqueued_jobs
        .find { |job| job[:job] == RailsErrorDashboard::AsyncErrorLoggingJob }
        .fetch(:args).to_json
      expect(queue_payload).not_to include("OMNI_SECRET")
      expect(queue_payload).not_to include("OMNI_PARAM")

      # 2. the export boundary -- the attributes any tracer would receive
      span_attributes = RailsErrorDashboard::Commands::LogError
        .build_capture_span_attributes(error, was_async: true)
      expect(span_attributes.to_json).not_to include("OMNI_SECRET")

      # 3. the stored row
      perform_enqueued_jobs
      row = logs.sole
      expect(row.message).not_to include("OMNI_SECRET")
      expect(row.request_params.to_s).not_to include("OMNI_PARAM")
    end
  end

  describe "the storm queue" do
    before do
      RailsErrorDashboard.configuration.enable_storm_protection = true
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)
    end

    it "buffers a redacted exemplar and an opaque identity, never the raw message" do
      gate.admit!(boom)
      snapshot = gate.count_buffer.snapshot!

      expect(snapshot.to_json).not_to include("QUEUE_SECRET")
      entry = snapshot[:entries].sole
      expect(entry["message"]).to eq("password=[FILTERED]")
      expect(entry["opaque_identity"]).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  # The property the two-stage hash exists to preserve. If the worker ever
  # recomputed the fingerprint from the redacted payload it would differ from
  # the sync path's, and one error would split across two rows.
  describe "grouping parity across all three paths" do
    it "lands a sync, an async and a storm capture of one error on one row" do
      RailsErrorDashboard.configuration.async_logging = false
      sync_row = RailsErrorDashboard::Commands::LogError.call(boom)

      RailsErrorDashboard.configuration.async_logging = true
      RailsErrorDashboard::Commands::LogError.call(boom)
      perform_enqueued_jobs

      RailsErrorDashboard.configuration.async_logging = false
      RailsErrorDashboard.configuration.enable_storm_protection = true
      allow(gate.breaker).to receive(:record!).and_return(:open)
      allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)
      gate.admit!(boom)
      snapshot = gate.count_buffer.snapshot!
      RailsErrorDashboard::Commands::FlushStormCounts.call(
        entries: snapshot[:entries], overflow: snapshot[:overflow]
      )

      row = logs.sole
      expect(row.id).to eq(sync_row.id)
      expect(row.error_hash).to eq(sync_row.error_hash)
      expect(row.occurrence_count).to eq(3)
    end
  end
end
