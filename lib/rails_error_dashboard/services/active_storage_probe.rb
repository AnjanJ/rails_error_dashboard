# frozen_string_literal: true

module RailsErrorDashboard
  module Services
    # Is the host's ActiveStorage service reachable right now?
    #
    # One existence check for a key that is never stored. The answer itself
    # (false) is irrelevant; the round trip is the test: Disk stats a path,
    # S3/GCS/Azure make one HEAD-style request. A raise (credentials, DNS, a
    # bucket that no longer exists, a disk that is not mounted) means the
    # service is down for the app too, which is what an operator wants to
    # know before the upload errors start.
    #
    # Read by the /health endpoint and the ActiveStorage Health page, both
    # on demand: nothing here runs on the capture path. Never raises.
    class ActiveStorageProbe
      # Namespaced so it cannot collide with a real blob key, which are
      # 28-character base36 tokens.
      PROBE_KEY = "rails_error_dashboard/health-probe"

      OK = "ok"
      DOWN = "down"
      SKIPPED = "skipped"

      def self.call
        new.call
      end

      def call
        return skipped("active_storage_not_loaded") unless defined?(::ActiveStorage)
        # Checked before ActiveStorage::Blob is touched: loading that class
        # reads config/storage.yml and raises when the file is missing, which
        # on a host that never set storage up is "not configured", not "down".
        return skipped("no_service_configured") unless configured?

        service = storage_service
        return skipped("no_service_configured") if service.nil?

        started = monotonic_now
        service.exist?(PROBE_KEY)

        { status: OK, service: service_name(service), latency_ms: elapsed_ms(started) }
      rescue => e
        # Class only: the message can carry a bucket name, a host or a path.
        { status: DOWN, service: safe_service_name(service), error: e.class.name }
      end

      private

      def skipped(reason)
        { status: SKIPPED, reason: reason }
      end

      # The configured service object. A seam: specs replace it with a double
      # rather than stubbing ActiveStorage::Blob, whose class load reads the
      # blobs table's schema (absent in the dummy app).
      def storage_service
        ::ActiveStorage::Blob.service
      end

      # config.active_storage.service names the service chosen for this
      # environment; nil when the app never configured storage.
      def configured?
        ::Rails.application.config.active_storage.service.present?
      rescue
        false
      end

      # The name from config/storage.yml ("amazon", "local"), which is what
      # the operator recognises; the class otherwise.
      def service_name(service)
        name = service.respond_to?(:name) ? service.name : nil
        name.presence&.to_s || service.class.name.to_s.demodulize.delete_suffix("Service").downcase
      end

      def safe_service_name(service)
        service ? service_name(service) : nil
      rescue
        nil
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started)
        ((monotonic_now - started) * 1000).round(2)
      end
    end
  end
end
