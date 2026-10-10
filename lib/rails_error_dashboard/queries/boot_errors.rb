# frozen_string_literal: true

module RailsErrorDashboard
  module Queries
    # Query: the crashes that happened while the process was still booting.
    #
    # A boot crash (a Zeitwerk::NameError from eager loading, a SyntaxError in
    # a model, an initializer that raised) is imported by CrashCapture with
    # platform "boot_crash" and the file and constant it names, when it names
    # them, in environment_info.boot. One entry per error row, most recent
    # first: the question is "what stopped the last deploy", not a frequency
    # ranking.
    class BootErrors
      PLATFORM = "boot_crash"

      def self.call(days = 30, application_id: nil)
        new(days, application_id: application_id).call
      end

      def initialize(days = 30, application_id: nil)
        @days = days
        @application_id = application_id
        @start_date = days.days.ago
      end

      # @return [Hash] entries: [{id:, error_type:, message:, file:, constant:,
      #   count:, first_seen:, last_seen:, resolved:}], unresolved_count: Integer
      def call
        rows = base_query
          .order(last_seen_at: :desc, id: :desc)
          .pluck(:id, :error_type, :message, :environment_info, :occurrence_count,
                 :first_seen_at, :last_seen_at, :resolved)

        entries = rows.map do |id, error_type, message, env_info, count, first_seen, last_seen, resolved|
          boot = boot_detail(env_info)
          {
            id: id,
            error_type: error_type.to_s,
            message: message.to_s,
            file: boot["file"].presence,
            constant: boot["constant"].presence,
            count: [ count.to_i, 1 ].max,
            first_seen: first_seen,
            last_seen: last_seen,
            resolved: resolved ? true : false
          }
        end

        { entries: entries, unresolved_count: entries.count { |e| !e[:resolved] } }
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] BootErrors query failed: #{e.class}: #{e.message}")
        { entries: [], unresolved_count: 0 }
      end

      private

      def base_query
        scope = ErrorLog.where(platform: PLATFORM).where("last_seen_at >= ?", @start_date)
        scope = scope.where(application_id: @application_id) if @application_id.present?
        scope
      end

      # environment_info is JSON text; the boot detail is optional and the
      # column may hold anything an older row wrote, so every step is guarded.
      def boot_detail(env_info)
        return {} if env_info.blank?

        parsed = env_info.is_a?(String) ? JSON.parse(env_info) : env_info
        boot = parsed.is_a?(Hash) ? parsed["boot"] : nil
        boot.is_a?(Hash) ? boot : {}
      rescue JSON::ParserError, TypeError
        {}
      end
    end
  end
end
