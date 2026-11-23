# frozen_string_literal: true

require "rails_helper"
require "net/smtp"

# hardening-1-0-rc2/REQ-29: a timeout, a refused connection, HTTP 429 or 5xx
#   (and an SMTP 4xx for email) schedules a retry.
# hardening-1-0-rc2/REQ-30: any other failure is logged and the job finishes.
# hardening-1-0-rc2/REQ-31: when retries run out, the cooldown claim
#   (error_logs.last_notified_at) is released, but only if it is still the
#   claim this job was given.
#
# Retries are asserted by the scheduled delay on the re-enqueued job, not by a
# raise: a retry_on that something else shadows still raises (lesson
# 2026-09-15).
RSpec.describe "Notification channel jobs retry transient failures", type: :job do
  # retry_on keys exception_executions by its exception list's to_s. Written
  # out, not read from the constant, so the examples that need it fail on
  # behaviour, not on a NameError, before the concern exists.
  def transient_key
    "[RailsErrorDashboard::Concerns::TransientDelivery::TransientDeliveryError]"
  end

  http_channels = {
    "SlackErrorNotificationJob" => {
      url: "https://hooks.slack.com/services/T/B/RETRY",
      setup: ->(config, url) { config.slack_webhook_url = url },
      builder: "SlackPayloadBuilder",
      label: /Slack/
    },
    "DiscordErrorNotificationJob" => {
      url: "https://discord.com/api/webhooks/1/retry",
      setup: ->(config, url) { config.discord_webhook_url = url },
      builder: "DiscordPayloadBuilder",
      label: /Discord/
    },
    "TelegramErrorNotificationJob" => {
      url: "https://api.telegram.org/bot123:RETRY-token/sendMessage",
      setup: ->(config, _url) {
        config.telegram_bot_token = "123:RETRY-token"
        config.telegram_chat_id = "@ops"
      },
      builder: "TelegramPayloadBuilder",
      label: /Telegram/
    },
    "PagerdutyErrorNotificationJob" => {
      url: "https://events.pagerduty.com/v2/enqueue",
      setup: ->(config, _url) { config.pagerduty_integration_key = "retry-routing-key" },
      builder: "PagerdutyPayloadBuilder",
      label: /PagerDuty/
    },
    "WebhookErrorNotificationJob" => {
      url: "https://example.com/hooks/retry",
      setup: ->(config, url) { config.webhook_urls = [ url ] },
      builder: "WebhookPayloadBuilder",
      label: /[Ww]ebhook/
    }
  }

  # SecurityError is critical, so PagerDuty sends too.
  let(:error_log) { create(:error_log, error_type: "SecurityError", message: "retry me") }
  # Nanoseconds, as Time.current has on Linux: the job carries this, the
  # column keeps microseconds, and the release must still match.
  let(:claimed_at) { Time.current.change(nsec: 123_456_789) }
  let(:stored_claim) { claimed_at.floor(6) }
  let(:log) { StringIO.new }

  around do |example|
    rails_logger = Rails.logger
    job_logger = ActiveJob::Base.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    ActiveJob::Base.logger = ActiveSupport::Logger.new(log)
    example.run
  ensure
    Rails.logger = rails_logger
    ActiveJob::Base.logger = job_logger
    RailsErrorDashboard.reset_configuration!
  end

  before do
    RailsErrorDashboard.configuration.dashboard_base_url = "https://example.com"
    error_log.update_columns(last_notified_at: claimed_at)
  end

  def retries_of(job)
    job.class.queue_adapter.enqueued_jobs.select { |data| data["job_id"] == job.job_id }
  end

  def expect_retry_scheduled(job)
    retries = retries_of(job)
    expect(retries.size).to eq(1), "expected one retry of #{job.class.name}, got #{retries.size}"
    # A delay means retry_on's wait ran; a bare re-raise would not schedule one.
    expect(retries.first[:at]).to be > Time.current.to_f
    # And the transient handler counted it, not ApplicationJob's StandardError one.
    expect(retries.first["exception_executions"]).to eq(transient_key => 1)
  end

  def run_after_two_failed_attempts(job)
    job.exception_executions = { transient_key => 2 }
    job.executions = 2
    job.perform_now
  end

  def cooldown_column
    RailsErrorDashboard::ErrorLog.where(id: error_log.id).pick(:last_notified_at)
  end

  http_channels.each do |job_name, channel|
    describe job_name do
      let(:job_class) { RailsErrorDashboard.const_get(job_name) }
      let(:url) { channel[:url] }
      let(:job) { job_class.new(error_log.id, "en", claimed_at) }

      before { channel[:setup].call(RailsErrorDashboard.configuration, url) }

      {
        "a timeout" => ->(stub) { stub.to_timeout },
        "a refused connection" => ->(stub) { stub.to_raise(Errno::ECONNREFUSED) },
        "HTTP 429" => ->(stub) { stub.to_return(status: 429, body: "slow down") },
        "HTTP 503" => ->(stub) { stub.to_return(status: 503, body: "unavailable") }
      }.each do |failure, respond|
        it "schedules a retry on #{failure} (REQ-29)" do
          respond.call(stub_request(:post, url))

          job.perform_now

          expect_retry_scheduled(job)
          expect(cooldown_column).to eq(stored_claim)
        end
      end

      it "schedules a retry for a job enqueued by rc.1, with no claim time (REQ-29)" do
        stub_request(:post, url).to_return(status: 503)
        legacy = job_class.new(error_log.id, "en")

        legacy.perform_now

        expect_retry_scheduled(legacy)
      end

      it "logs an HTTP 400 and finishes without a retry (REQ-30)" do
        stub_request(:post, url).to_return(status: 400, body: "bad request")

        job.perform_now

        expect(retries_of(job)).to be_empty
        expect(log.string).to match(channel[:label]).and match(/400/)
        expect(cooldown_column).to eq(stored_claim)
      end

      it "logs an unexpected error and finishes without a retry (REQ-30)" do
        stub_request(:post, url).to_return(status: 200)
        allow(RailsErrorDashboard::Services.const_get(channel[:builder]))
          .to receive(:call).and_raise(RuntimeError, "builder broke")

        job.perform_now

        expect(retries_of(job)).to be_empty
        expect(log.string).to match(channel[:label]).and match(/builder broke/)
      end

      context "when the third attempt fails too (REQ-31)" do
        before { stub_request(:post, url).to_return(status: 503) }

        it "releases the claim it was given" do
          run_after_two_failed_attempts(job)

          expect(retries_of(job)).to be_empty
          expect(cooldown_column).to be_nil
          expect(log.string).to match(/3 attempts/)
        end

        it "keeps a newer claim another notification took" do
          newer = stored_claim + 1.minute
          error_log.update_columns(last_notified_at: newer)

          run_after_two_failed_attempts(job)

          expect(cooldown_column).to eq(newer)
        end

        if job_name == "TelegramErrorNotificationJob"
          it "logs the last failure with the bot token redacted" do
            stub_request(:post, url).to_raise(SocketError.new("getaddrinfo failed for #{url}"))

            run_after_two_failed_attempts(job)

            expect(log.string).to match(/gave up after 3 attempts/)
            expect(log.string).not_to include("RETRY-token")
          end
        end

        it "releases nothing when enqueued without a claim time, as rc.1 did" do
          legacy = job_class.new(error_log.id, "en")

          run_after_two_failed_attempts(legacy)

          expect(retries_of(legacy)).to be_empty
          expect(cooldown_column).to eq(stored_claim)
        end
      end
    end
  end

  describe "WebhookErrorNotificationJob with several URLs" do
    let(:urls) { [ "https://example.com/hooks/down", "https://example.com/hooks/up" ] }
    let(:job) { RailsErrorDashboard::WebhookErrorNotificationJob.new(error_log.id, "en", claimed_at) }

    before { RailsErrorDashboard.configuration.webhook_urls = urls }

    it "posts every URL before a 503 retries the job (REQ-29)" do
      stub_request(:post, urls.first).to_return(status: 503)
      stub_request(:post, urls.last).to_return(status: 200)

      job.perform_now

      expect(WebMock).to have_requested(:post, urls.first).once
      expect(WebMock).to have_requested(:post, urls.last).once
      expect_retry_scheduled(job)
    end
  end

  describe "EmailErrorNotificationJob" do
    let(:job_class) { RailsErrorDashboard::EmailErrorNotificationJob }
    let(:job) { job_class.new(error_log.id, "en", claimed_at) }
    let(:delivery) { instance_double(ActionMailer::MessageDelivery) }

    before do
      RailsErrorDashboard.configuration.notification_email_recipients = [ "ops@example.com" ]
      allow(RailsErrorDashboard::ErrorNotificationMailer).to receive(:error_alert).and_return(delivery)
    end

    def smtp_error(klass, line)
      klass.new(Net::SMTP::Response.parse(line))
    end

    {
      "a timeout" => -> { Net::ReadTimeout.new },
      "a refused connection" => -> { Errno::ECONNREFUSED.new },
      "an SMTP 4xx" => -> { Net::SMTPServerBusy.new(Net::SMTP::Response.parse("421 4.7.0 try again later")) }
    }.each do |failure, error|
      it "schedules a retry on #{failure} (REQ-29)" do
        allow(delivery).to receive(:deliver_now).and_raise(error.call)

        job.perform_now

        expect_retry_scheduled(job)
      end
    end

    it "logs an SMTP 5xx and finishes without a retry (REQ-30)" do
      allow(delivery).to receive(:deliver_now)
        .and_raise(smtp_error(Net::SMTPFatalError, "550 5.1.1 no such user"))

      job.perform_now

      expect(retries_of(job)).to be_empty
      expect(log.string).to match(/email/).and match(/550/)
    end

    it "logs an unexpected error and finishes without a retry (REQ-30)" do
      allow(delivery).to receive(:deliver_now).and_raise(RuntimeError, "template broke")

      job.perform_now

      expect(retries_of(job)).to be_empty
      expect(log.string).to match(/email/).and match(/template broke/)
    end

    it "releases the claim when the third attempt fails too (REQ-31)" do
      allow(delivery).to receive(:deliver_now).and_raise(Errno::ECONNREFUSED)

      run_after_two_failed_attempts(job)

      expect(retries_of(job)).to be_empty
      expect(cooldown_column).to be_nil
    end
  end

  describe "which errors are transient (REQ-29, REQ-30)" do
    let(:klass) { RailsErrorDashboard::SlackErrorNotificationJob }

    {
      "Net::OpenTimeout" => -> { Net::OpenTimeout.new },
      "Net::ReadTimeout" => -> { Net::ReadTimeout.new },
      "Errno::ETIMEDOUT" => -> { Errno::ETIMEDOUT.new },
      "Errno::ECONNREFUSED" => -> { Errno::ECONNREFUSED.new },
      "Errno::ECONNRESET" => -> { Errno::ECONNRESET.new },
      "SocketError (DNS)" => -> { SocketError.new("getaddrinfo: nodename nor servname provided") },
      "Net::SMTPServerBusy (SMTP 4xx)" => -> { Net::SMTPServerBusy.new(Net::SMTP::Response.parse("451 try later")) }
    }.each do |name, error|
      it "retries #{name}" do
        expect(klass.transient_error?(error.call)).to be(true)
      end
    end

    {
      "Net::SMTPFatalError (SMTP 5xx)" => -> { Net::SMTPFatalError.new(Net::SMTP::Response.parse("550 no such user")) },
      "OpenSSL::SSL::SSLError" => -> { OpenSSL::SSL::SSLError.new("certificate verify failed") },
      "RuntimeError" => -> { RuntimeError.new("bug") }
    }.each do |name, error|
      it "does not retry #{name}" do
        expect(klass.transient_error?(error.call)).to be(false)
      end
    end

    it "retries HTTP 429 and 5xx and nothing else" do
      retried = [ 200, 301, 400, 401, 404, 408, 429, 499, 500, 502, 503, 599, 600 ].select { |code| klass.transient_status?(code) }

      expect(retried).to eq([ 429, 500, 502, 503, 599 ])
    end
  end

  # :inline (and Resque without a scheduler, Sneakers, queue_classic) raise
  # NotImplementedError from enqueue_at. It is a ScriptError, so no rescue on
  # the capture path stops it, and under :inline the job runs inside
  # perform_later, on the thread that captured the error. Stubbed on the
  # adapter, not swapped: swapping adapters leaks between specs.
  describe "a queue adapter that cannot schedule a retry (REQ-29, REQ-31)" do
    let(:job_class) { RailsErrorDashboard::WebhookErrorNotificationJob }
    let(:job) { job_class.new(error_log.id, "en", claimed_at) }

    before do
      RailsErrorDashboard.configuration.webhook_urls = [ "https://example.com/hooks/inline" ]
      stub_request(:post, "https://example.com/hooks/inline").to_raise(Errno::ECONNREFUSED)
      allow(job_class.queue_adapter).to receive(:enqueue_at)
        .and_raise(NotImplementedError, "Use a queueing backend to enqueue jobs in the future.")
    end

    it "treats the failed attempt as the last one, without raising" do
      expect { job.perform_now }.not_to raise_error

      expect(cooldown_column).to be_nil
      expect(log.string).to match(/could not schedule a retry/)
    end
  end

  describe "releasing the claim" do
    it "never raises when the release cannot be written (REQ-31)" do
      allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect(RailsErrorDashboard::Services::NotificationThrottler.release!(error_log.id, claimed_at)).to be(false)
    end
  end

  describe "the handler order" do
    (http_channels.keys + [ "EmailErrorNotificationJob" ]).each do |job_name|
      it "checks TransientDeliveryError before StandardError on #{job_name}" do
        handlers = RailsErrorDashboard.const_get(job_name).rescue_handlers.map(&:first)
        transient = handlers.rindex { |name| name.end_with?("::TransientDeliveryError") }

        # rescue_handlers resolve from the end, so a later entry is checked first.
        expect(transient).not_to be_nil
        expect(transient).to be > handlers.rindex("StandardError")
      end
    end
  end

  describe "the claim time reaching the jobs (REQ-31)" do
    before do
      config = RailsErrorDashboard.configuration
      http_channels.each_value { |channel| channel[:setup].call(config, channel[:url]) }
      config.notification_email_recipients = [ "ops@example.com" ]
      config.enable_slack_notifications = true
      config.enable_email_notifications = true
      config.enable_discord_notifications = true
      config.enable_telegram_notifications = true
      config.enable_pagerduty_notifications = true
      config.enable_webhook_notifications = true
    end

    it "gives every channel's job the time LogError wrote to last_notified_at" do
      # SecurityError is critical, so the PagerDuty job is enqueued too.
      RailsErrorDashboard::Commands::LogError.call(SecurityError.new("claim time #{SecureRandom.hex(4)}"), {})

      channel_jobs = (http_channels.keys + [ "EmailErrorNotificationJob" ]).map { |name| RailsErrorDashboard.const_get(name) }
      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |data| channel_jobs.include?(data[:job]) }
      expect(enqueued.map { |data| data[:job] }).to match_array(channel_jobs)

      enqueued.each do |data|
        error_log_id, _locale, job_claimed_at = ActiveJob::Arguments.deserialize(data[:args])
        expect(job_claimed_at).not_to be_nil, "#{data[:job]} was enqueued without a claim time"
        matched = RailsErrorDashboard::ErrorLog.where(id: error_log_id, last_notified_at: job_claimed_at).count
        expect(matched).to eq(1), "#{data[:job]}'s claim time does not match last_notified_at"
      end
    end
  end
end
