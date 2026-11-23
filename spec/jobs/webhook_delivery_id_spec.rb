# frozen_string_literal: true

require "rails_helper"

# hardening-1-0-rc2/REQ-32: every webhook post carries a delivery id that is
# the same on every retry of that post. One job per URL, so a retry re-posts
# only the URL that failed.
RSpec.describe "Webhook delivery ids", type: :job do
  let(:error_log) { create(:error_log) }
  let(:urls) { [ "https://example.com/hooks/one?token=s3cret", "https://example.com/hooks/two" ] }
  let(:job_class) { RailsErrorDashboard::WebhookErrorNotificationJob }
  let(:header) { "X-Error-Dashboard-Delivery" }

  before do
    config = RailsErrorDashboard.configuration
    config.enable_webhook_notifications = true
    config.webhook_urls = urls
    config.dashboard_base_url = "https://example.com"
  end

  after { RailsErrorDashboard.reset_configuration! }

  # url => [delivery ids it received, in order]
  def record_deliveries(*responses_by_url)
    received = Hash.new { |hash, key| hash[key] = [] }
    responses_by_url.each do |url, responses|
      stub_request(:post, url)
        .with { |request| received[url] << request.headers[header]; true }
        .to_return(*responses)
    end
    received
  end

  def enqueued_webhook_jobs
    job_class.queue_adapter.enqueued_jobs.select { |data| data[:job] == job_class }
  end

  it "enqueues one job per URL, and each posts its own URL once" do
    received = record_deliveries([ urls.first, [ { status: 200 } ] ], [ urls.last, [ { status: 200 } ] ])

    RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)
    jobs = enqueued_webhook_jobs
    expect(jobs.size).to eq(2)
    jobs.each { |data| ActiveJob::Base.deserialize(data).perform_now }

    expect(received[urls.first].size).to eq(1)
    expect(received[urls.last].size).to eq(1)
  end

  it "posts a URL listed twice in webhook_urls once" do
    RailsErrorDashboard.configuration.webhook_urls = [ urls.first, urls.first ]
    received = record_deliveries([ urls.first, [ { status: 200 } ] ])

    RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)
    enqueued_webhook_jobs.each { |data| ActiveJob::Base.deserialize(data).perform_now }

    expect(enqueued_webhook_jobs.size).to eq(1)
    expect(received[urls.first].size).to eq(1)
  end

  it "keeps the URLs, which can carry a token, out of the job's arguments" do
    RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)

    expect(enqueued_webhook_jobs.map { |data| data[:args].to_s }.join).not_to include("example.com")
  end

  it "sends the same delivery id when a failed post is retried" do
    RailsErrorDashboard.configuration.webhook_urls = [ urls.first ]
    received = record_deliveries([ urls.first, [ { status: 503 }, { status: 200 } ] ])

    RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)
    first = ActiveJob::Base.deserialize(enqueued_webhook_jobs.first)
    first.perform_now
    retried = enqueued_webhook_jobs.select { |data| data["job_id"] == first.job_id && data[:at] }
    expect(retried.size).to eq(1)
    ActiveJob::Base.deserialize(retried.first).perform_now

    ids = received[urls.first]
    expect(ids.size).to eq(2)
    expect(ids.first).to match(/\A\h{32}\z/)
    expect(ids.last).to eq(ids.first)
  end

  it "sends different delivery ids from two jobs for the same URL" do
    RailsErrorDashboard.configuration.webhook_urls = [ urls.first ]
    received = record_deliveries([ urls.first, [ { status: 200 } ] ])

    2.times { RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log) }
    enqueued_webhook_jobs.each { |data| ActiveJob::Base.deserialize(data).perform_now }

    expect(received[urls.first].size).to eq(2)
    expect(received[urls.first].uniq.size).to eq(2)
  end

  it "still posts every URL from a job enqueued by rc.1, each with its own id" do
    received = record_deliveries([ urls.first, [ { status: 200 } ] ], [ urls.last, [ { status: 200 } ] ])

    job_class.new(error_log.id, "en").perform_now

    expect(received[urls.first].size).to eq(1)
    expect(received[urls.last].size).to eq(1)
    expect(received[urls.first].first).not_to eq(received[urls.last].first)
  end

  it "posts nothing when the job's URL was removed from webhook_urls before it ran" do
    received = record_deliveries([ urls.first, [ { status: 200 } ] ], [ urls.last, [ { status: 200 } ] ])

    RailsErrorDashboard::Services::ErrorNotificationDispatcher.call(error_log)
    RailsErrorDashboard.configuration.webhook_urls = [ urls.last ]
    enqueued_webhook_jobs.each { |data| ActiveJob::Base.deserialize(data).perform_now }

    expect(received[urls.first]).to be_empty
    expect(received[urls.last].size).to eq(1)
  end

  # Storm, burst-summary and baseline posts are never retried (each post is
  # rescued), so a fresh id per post meets REQ-32 for them.
  it "gives a post without a job a delivery id too" do
    received = record_deliveries([ urls.last, [ { status: 200 } ] ])

    RailsErrorDashboard::Services::WebhookDelivery.post(urls.last, { event: "storm.detected" })

    expect(received[urls.last].first).to match(/\A\h{32}\z/)
  end
end
