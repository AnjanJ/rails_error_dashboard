# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::CloseLinkedIssueJob do
  let(:error_log) { create(:error_log, occurred_at: 1.day.ago, external_issue_url: "https://github.com/user/repo/issues/42", external_issue_number: 42, external_issue_provider: "github", resolved_by_name: "gandalf") }

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_tracker_provider = :github
    RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
    RailsErrorDashboard.configuration.issue_tracker_repo = "user/repo"
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "adds comment and closes the linked issue" do
    stub_request(:post, "https://api.github.com/repos/user/repo/issues/42/comments")
      .to_return(status: 201, body: { html_url: "https://github.com/..." }.to_json)
    stub_request(:patch, "https://api.github.com/repos/user/repo/issues/42")
      .with(body: hash_including("state" => "closed"))
      .to_return(status: 200, body: {}.to_json)

    described_class.perform_now(error_log.id)
  end

  it "skips when no linked issue" do
    error_log.update!(external_issue_url: nil, external_issue_number: nil)
    expect { described_class.perform_now(error_log.id) }.not_to raise_error
  end
end

RSpec.describe RailsErrorDashboard::ReopenLinkedIssueJob do
  let(:error_log) { create(:error_log, occurred_at: 1.day.ago, external_issue_url: "https://github.com/user/repo/issues/42", external_issue_number: 42, external_issue_provider: "github", occurrence_count: 5) }

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_tracker_provider = :github
    RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
    RailsErrorDashboard.configuration.issue_tracker_repo = "user/repo"
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "reopens the linked issue and adds recurrence comment" do
    stub_request(:patch, "https://api.github.com/repos/user/repo/issues/42")
      .with(body: hash_including("state" => "open"))
      .to_return(status: 200, body: {}.to_json)
    stub_request(:post, "https://api.github.com/repos/user/repo/issues/42/comments")
      .to_return(status: 201, body: { html_url: "https://github.com/..." }.to_json)

    described_class.perform_now(error_log.id)
  end
end

RSpec.describe RailsErrorDashboard::AddIssueRecurrenceCommentJob do
  let(:error_log) { create(:error_log, occurred_at: 1.day.ago, external_issue_url: "https://github.com/user/repo/issues/42", external_issue_number: 42, external_issue_provider: "github", occurrence_count: 10) }

  before do
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_tracker_provider = :github
    RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
    RailsErrorDashboard.configuration.issue_tracker_repo = "user/repo"
    described_class.class_variable_set(:@@last_comment_at, {})
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "adds a recurrence comment" do
    stub_request(:post, "https://api.github.com/repos/user/repo/issues/42/comments")
      .to_return(status: 201, body: { html_url: "https://github.com/..." }.to_json)

    described_class.perform_now(error_log.id)
  end

  it "throttles to 1 comment per hour" do
    described_class.class_variable_get(:@@last_comment_at)[error_log.id] = Time.current

    # Should not make any API call
    described_class.perform_now(error_log.id)
  end
end
