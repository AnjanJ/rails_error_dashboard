# frozen_string_literal: true

module RailsErrorDashboard
  class ApplicationMailer < ActionMailer::Base
    default from: -> { RailsErrorDashboard.configuration.notification_email_from }
    layout false

    # Mailers do not pick up engine helpers the way controllers do, so red_t
    # is included explicitly. Mailers render outside a request, where
    # Current.locale is nil — red_locale therefore resolves to
    # config.dashboard_locale. Phase 4 passes an explicit locale through job
    # arguments instead of relying on that, because a job may run on a thread
    # whose Current was set by an unrelated request.
    helper RailsErrorDashboard::I18nHelper
  end
end
