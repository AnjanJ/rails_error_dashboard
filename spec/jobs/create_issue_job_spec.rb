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
end
