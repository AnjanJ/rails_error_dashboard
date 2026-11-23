# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::CreateIssueJob do
  let(:error_log) { create(:error_log, occurred_at: 1.day.ago) }

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_tracker_provider = :github
    RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
    RailsErrorDashboard.configuration.issue_tracker_repo = "user/repo"
    described_class.class_variable_set(:@@recent_failures, [])
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "creates an issue via CreateIssue command" do
    stub_request(:post, "https://api.github.com/repos/user/repo/issues")
      .to_return(status: 201, body: { html_url: "https://github.com/user/repo/issues/1", number: 1 }.to_json)

    described_class.perform_now(error_log.id)

    error_log.reload
    expect(error_log.external_issue_url).to eq("https://github.com/user/repo/issues/1")
  end

  it "skips when circuit breaker is open" do
    # Fill circuit breaker
    5.times { described_class.class_variable_get(:@@recent_failures) << Time.current }

    described_class.perform_now(error_log.id)
    error_log.reload
    expect(error_log.external_issue_url).to be_nil
  end

  it "does not retry when error already has a linked issue" do
    error_log.update!(external_issue_url: "https://github.com/user/repo/issues/99")

    expect { described_class.perform_now(error_log.id) }.not_to raise_error
  end

  def failures
    described_class.class_variable_get(:@@recent_failures).size
  end

  def retries_of(job)
    described_class.queue_adapter.enqueued_jobs.select { |data| data["job_id"] == job.job_id && data[:at] }
  end

  # hardening-1-0-rc2/REQ-34
  it "counts a failed result as one failure, and retries it" do
    stub_request(:post, "https://api.github.com/repos/user/repo/issues")
      .to_return(status: 422, body: { message: "Validation Failed" }.to_json)
    job = described_class.new(error_log.id)

    job.perform_now

    expect(failures).to eq(1)
    expect(retries_of(job).size).to eq(1)
  end

  it "counts an error raised outside the command as one failure" do
    allow(RailsErrorDashboard::Commands::CreateIssue).to receive(:call).and_raise(RuntimeError, "boom")
    job = described_class.new(error_log.id)

    job.perform_now

    expect(failures).to eq(1)
    expect(retries_of(job).size).to eq(1)
  end

  # hardening-1-0-rc2/REQ-35. The command's messages follow dashboard_locale
  # (Translation#red_t reads Current.locale_or_default, not I18n.locale), so
  # both are set, and each example first checks the message is German: in
  # English the old check on the text passed too.
  context "in German" do
    around do |example|
      RailsErrorDashboard.configuration.dashboard_locale = "de"
      I18n.with_locale(:de) { example.run }
    end

    it "does not retry when the error already has an issue" do
      error_log.update!(external_issue_url: "https://github.com/user/repo/issues/99")
      expect(RailsErrorDashboard::Commands::CreateIssue.call(error_log.id)[:error]).to include("bereits")
      job = described_class.new(error_log.id)

      job.perform_now

      expect(retries_of(job)).to be_empty
    end

    it "does not retry when issue tracking is not configured" do
      RailsErrorDashboard.configuration.enable_issue_tracking = false
      expect(RailsErrorDashboard::Commands::CreateIssue.call(error_log.id)[:error]).to include("nicht konfiguriert")
      job = described_class.new(error_log.id)

      job.perform_now

      expect(retries_of(job)).to be_empty
    end
  end

  it "does not retry when the error is gone" do
    job = described_class.new(999_999)

    job.perform_now

    expect(retries_of(job)).to be_empty
  end
end
