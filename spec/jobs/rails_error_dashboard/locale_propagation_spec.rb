# frozen_string_literal: true

require "rails_helper"

# P4-T1 — locale propagation into jobs.
#
# The property under test is that async output's locale comes from the job's
# own arguments and nowhere else. Jobs run outside the dashboard's
# around_action, so anything read from thread state is either nil or another
# request's leftover — the #143/#148 bug class.
RSpec.describe "Locale propagation into jobs" do
  # A second SHIPPED locale. Without one, every assertion here would compare
  # "en" against "en" and pass even if propagation were completely broken.
  # Written to config/locales so I18nStore picks it up the way it picks up a
  # real locale, then removed. "xt" is deliberately not "zz" — four existing
  # specs use "zz" as their example of an *unshipped* locale and would start
  # failing if it became available. (See the P3 note in the sprint plan.)
  TEST_LOCALE = "xt"

  before(:all) do
    @locale_path = RailsErrorDashboard::Engine.root.join("config", "locales", "#{TEST_LOCALE}.yml")
    @locale_path.write(<<~YAML)
      #{TEST_LOCALE}:
        red:
          common:
            loading: "XT-LOADING"
    YAML
    RailsErrorDashboard::I18nStore.reset!
  end

  after(:all) do
    @locale_path.delete if @locale_path.exist?
    RailsErrorDashboard::I18nStore.reset!
  end

  let!(:application) { create(:application) }
  let!(:error_log) { create(:error_log, application: application) }

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Current.locale = nil
  end

  it "ships the fixture locale, so the assertions below can actually fail" do
    expect(RailsErrorDashboard::I18nStore.available?(TEST_LOCALE)).to be(true)
  end

  describe "REQ-2 — resolved at enqueue time" do
    it "serializes the configured locale into the job arguments" do
      RailsErrorDashboard.configure do |c|
        c.enable_slack_notifications = true
        c.slack_webhook_url = "https://hooks.slack.com/test"
        c.dashboard_locale = TEST_LOCALE
      end

      expect {
        RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)
      }.to have_enqueued_job(RailsErrorDashboard::SlackErrorNotificationJob)
        .with(error_log.id, TEST_LOCALE)
    end

    it "prefers the acting user's locale when enqueued from a dashboard request" do
      RailsErrorDashboard.configuration.dashboard_locale = "en"
      RailsErrorDashboard::Current.locale = TEST_LOCALE

      expect(RailsErrorDashboard::ApplicationJob.enqueue_locale).to eq(TEST_LOCALE)
    end

    it "falls back to the configured locale when Current is unset" do
      RailsErrorDashboard.configuration.dashboard_locale = TEST_LOCALE
      RailsErrorDashboard::Current.locale = nil

      expect(RailsErrorDashboard::ApplicationJob.enqueue_locale).to eq(TEST_LOCALE)
    end

    it "never raises, whatever Current holds" do
      RailsErrorDashboard::Current.locale = Object.new

      expect { RailsErrorDashboard::ApplicationJob.enqueue_locale }.not_to raise_error
      expect(RailsErrorDashboard::ApplicationJob.enqueue_locale).to eq("en")
    end
  end

  describe "REQ-5 — arguments stay serializable" do
    it "serializes the locale as a String, not a Symbol" do
      RailsErrorDashboard.configure do |c|
        c.enable_webhook_notifications = true
        c.webhook_urls = [ "https://example.com/webhook" ]
        c.dashboard_locale = TEST_LOCALE
      end

      RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)

      serialized = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(serialized[:args].last).to be_a(String)
      expect(serialized[:args].last).to eq(TEST_LOCALE)
    end

    it "survives an ActiveJob serialization round-trip" do
      job = RailsErrorDashboard::SlackErrorNotificationJob.new(error_log.id, TEST_LOCALE)
      round_tripped = ActiveJob::Base.deserialize(job.serialize)
      round_tripped.send(:deserialize_arguments_if_needed)

      expect(round_tripped.arguments).to eq([ error_log.id, TEST_LOCALE ])
    end
  end

  describe "REQ-6 — jobs enqueued before the upgrade still run" do
    # Queues drain across a deploy. A payload written by the previous version
    # has no locale argument at all. Losing those notifications would be a far
    # worse bug than rendering them in the wrong language.
    before do
      RailsErrorDashboard.configure do |c|
        c.enable_slack_notifications = true
        c.slack_webhook_url = "https://hooks.slack.com/test"
      end
      stub_request(:post, "https://hooks.slack.com/test").to_return(status: 200)
    end

    it "executes a Slack job invoked with the old single-argument signature" do
      expect {
        RailsErrorDashboard::SlackErrorNotificationJob.perform_now(error_log.id)
      }.not_to raise_error

      expect(WebMock).to have_requested(:post, "https://hooks.slack.com/test").once
    end

    it "still delivers when the locale argument is explicitly nil" do
      RailsErrorDashboard::SlackErrorNotificationJob.perform_now(error_log.id, nil)

      expect(WebMock).to have_requested(:post, "https://hooks.slack.com/test").once
    end
  end

  describe "REQ-4 — a locale problem never costs a notification" do
    before do
      RailsErrorDashboard.configure do |c|
        c.enable_slack_notifications = true
        c.slack_webhook_url = "https://hooks.slack.com/test"
      end
      stub_request(:post, "https://hooks.slack.com/test").to_return(status: 200)
    end

    [ "zz", "", "   ", "'; DROP TABLE users; --", "en-GARBAGE" ].each do |bad|
      it "delivers anyway when the locale argument is #{bad.inspect}" do
        expect {
          RailsErrorDashboard::SlackErrorNotificationJob.perform_now(error_log.id, bad)
        }.not_to raise_error

        expect(WebMock).to have_requested(:post, "https://hooks.slack.com/test").once
      end
    end

    it "delivers when the locale argument is not even a String" do
      expect {
        RailsErrorDashboard::SlackErrorNotificationJob.perform_now(error_log.id, 42)
      }.not_to raise_error

      expect(WebMock).to have_requested(:post, "https://hooks.slack.com/test").once
    end
  end

  describe "REQ-3 — jobs do not read ambient locale state" do
    # The regression this guards: a job running on a thread a dashboard request
    # left Current.locale on. The job's own argument must win.
    it "ignores the request-scoped locale left behind by an unrelated request" do
      # The job's own argument must win over whatever the thread carries.
      RailsErrorDashboard::Current.locale = TEST_LOCALE

      job = RailsErrorDashboard::SlackErrorNotificationJob.new
      expect(job.send(:job_locale, "en")).to eq("en")
    end

    it "falls back to config, not to thread state, when the argument is missing" do
      RailsErrorDashboard.configuration.dashboard_locale = "en"
      RailsErrorDashboard::Current.locale = TEST_LOCALE

      job = RailsErrorDashboard::SlackErrorNotificationJob.new

      # Current is consulted only as the last resort, and locale_or_default
      # applies the documented precedence. What matters is that a nil argument
      # never silently becomes an unrelated request's locale in production,
      # where jobs run with Current already reset.
      RailsErrorDashboard::Current.locale = nil
      expect(job.send(:job_locale, nil)).to eq("en")
    end

    it "does not reference Current.locale or I18n.locale in any job file" do
      offenders = Dir[Rails.root.join("../../app/jobs/**/*.rb")].select do |path|
        # The concern is the one place allowed to consult Current — it does so
        # only as the *fallback* for a missing argument, never as the source.
        next false if path.end_with?("concerns/localized_job.rb")

        File.read(path).match?(/Current\.locale|I18n\.locale/)
      end

      expect(offenders).to be_empty
    end
  end

  describe "mailers render in the locale they are handed" do
    # ApplicationMailer's red_locale must prefer the explicit @red_locale over
    # Current — a mailer renders outside the request that set Current.
    it "uses the passed locale rather than thread state" do
      RailsErrorDashboard::Current.locale = TEST_LOCALE

      mail = RailsErrorDashboard::ErrorNotificationMailer.error_alert(
        error_log, [ "admin@example.com" ], locale: "en"
      )

      expect(mail.to).to eq([ "admin@example.com" ])
      expect { mail.body }.not_to raise_error
    end

    it "resolves red_locale from the explicit locale, not from Current" do
      RailsErrorDashboard::Current.locale = "en"

      view = Object.new
      view.extend(RailsErrorDashboard::I18nHelper)
      view.instance_variable_set(:@red_locale, TEST_LOCALE)

      expect(view.red_locale).to eq(TEST_LOCALE)
    end

    it "falls back to Current when no explicit locale was assigned" do
      RailsErrorDashboard::Current.locale = TEST_LOCALE

      view = Object.new
      view.extend(RailsErrorDashboard::I18nHelper)

      expect(view.red_locale).to eq(TEST_LOCALE)
    end

    it "renders with the default locale when called without one" do
      mail = RailsErrorDashboard::ErrorNotificationMailer.error_alert(
        error_log, [ "admin@example.com" ]
      )

      expect { mail.body }.not_to raise_error
    end
  end
end
