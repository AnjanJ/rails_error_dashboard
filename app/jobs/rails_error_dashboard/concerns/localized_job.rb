# frozen_string_literal: true

module RailsErrorDashboard
  module Concerns
    # Gives a job an explicit, serialized locale instead of an inherited one.
    #
    # WHY JOBS CANNOT JUST READ Current.locale
    #
    # Mailers and notification jobs render outside the dashboard's
    # around_action. There is no request, so there is no request locale.
    # Reading Current.locale in a job returns nil at best — and at worst, on a
    # reused Puma or job-runner thread, whatever an unrelated request left
    # behind. That is the same bug class as #143 and #148: state outliving the
    # request that set it.
    #
    # So the locale is resolved at ENQUEUE time (see .enqueue_locale) and
    # travels in the job's arguments. The job then reads only its own argument.
    #
    # WHY ENQUEUE TIME RESOLVES TO CONFIG, NOT TO A USER
    #
    # Notifications are enqueued from the capture path — log_error, the storm
    # gate — which runs inside a *host app* request, not a dashboard one. There
    # is no dashboard user in scope and Current.locale is correctly nil there.
    # The meaningful answer is config.dashboard_locale, which is what
    # Current.locale_or_default returns when Current.locale is unset. Resolving
    # through that one path keeps a single precedence chain for the whole gem
    # and lets a dashboard-initiated enqueue (a future "send test notification"
    # button) pick up the acting user's locale for free.
    #
    # BACKWARD COMPATIBILITY IS NOT OPTIONAL HERE
    #
    # Queues drain across a deploy. Jobs enqueued by the previous version have
    # no locale argument at all, and they must still run — a notification is
    # never worth losing over a translation detail. Every consumer therefore
    # defaults the argument, and #job_locale hardens whatever arrives.
    module LocalizedJob
      extend ActiveSupport::Concern

      class_methods do
        # The locale to serialize into a job's arguments, resolved in the
        # enqueueing thread while its context is still valid.
        #
        # Returns a String, never a Symbol: ActiveJob serializes Symbols
        # inconsistently across adapters, and Sidekiq's JSON round-trip turns
        # one into a String anyway. Being explicit avoids a locale that is a
        # Symbol on the inline adapter and a String in production.
        #
        # @return [String] a locale RED ships. Never nil, never raises.
        def enqueue_locale
          Current.locale_or_default
        rescue StandardError
          I18nStore::DEFAULT_LOCALE
        end
      end

      private

      # The locale this job should render in, from its own argument.
      #
      # Total by design. A nil (pre-upgrade payload), a garbage string, a
      # Symbol, or a locale RED does not ship all degrade to
      # config.dashboard_locale and then to English. REQ-4: a notification must
      # never be lost because of a locale problem.
      #
      # @param value [Object] whatever arrived in the job arguments
      # @return [String] a locale RED ships
      def job_locale(value)
        candidate = value.to_s.strip
        return Current.locale_or_default if candidate.empty?

        # resolve/1 already degrades an unknown tag to English, but an unknown
        # tag should first get a chance at the configured locale — a queued job
        # carrying a stale tag is closer to "no opinion" than to "wants
        # English".
        return I18nStore.resolve(candidate) if I18nStore.available?(candidate)

        Current.locale_or_default
      rescue StandardError
        I18nStore::DEFAULT_LOCALE
      end
    end
  end
end
