# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Subscribers::IssueTrackerSubscriber do
  include ActiveJob::TestHelper

  let(:error_log) { create(:error_log, occurred_at: 1.day.ago) }

  before do
    ActiveJob::Base.queue_adapter = :test
    RailsErrorDashboard.configuration.enable_issue_tracking = true
    RailsErrorDashboard.configuration.issue_tracker_provider = :github
    RailsErrorDashboard.configuration.issue_tracker_token = "ghp_test"
    RailsErrorDashboard.configuration.issue_tracker_repo = "user/repo"
    RailsErrorDashboard.configuration.issue_tracker_auto_create_severities = [ :critical, :high ]
  end

  after { RailsErrorDashboard.reset_configuration! }

  describe ".on_error_logged" do
    it "enqueues CreateIssueJob for first occurrence" do
      error_log.update!(occurrence_count: 1)
      expect(RailsErrorDashboard::CreateIssueJob).to receive(:perform_later).with(error_log.id, dashboard_url: anything)
      described_class.on_error_logged(error_log)
    end

    it "skips when issue tracking is disabled" do
      RailsErrorDashboard.configuration.enable_issue_tracking = false
      error_log.update!(occurrence_count: 1)
      expect(RailsErrorDashboard::CreateIssueJob).not_to receive(:perform_later)
      described_class.on_error_logged(error_log)
    end

    it "skips when error already has a linked issue" do
      error_log.update!(occurrence_count: 1, external_issue_url: "https://github.com/user/repo/issues/1")
      expect(RailsErrorDashboard::CreateIssueJob).not_to receive(:perform_later)
      described_class.on_error_logged(error_log)
    end

    it "enqueues for high severity even if not first occurrence" do
      error_log.update!(occurrence_count: 5)
      allow(error_log).to receive(:severity).and_return("high")
      expect(RailsErrorDashboard::CreateIssueJob).to receive(:perform_later).with(error_log.id, dashboard_url: anything)
      described_class.on_error_logged(error_log)
    end

    it "skips low severity non-first occurrence" do
      error_log.update!(occurrence_count: 5)
      allow(error_log).to receive(:severity).and_return("low")
      expect(RailsErrorDashboard::CreateIssueJob).not_to receive(:perform_later)
      described_class.on_error_logged(error_log)
    end
  end

  describe ".on_error_resolved" do
    it "enqueues CloseLinkedIssueJob when issue is linked" do
      error_log.update!(external_issue_url: "https://github.com/user/repo/issues/42")
      expect(RailsErrorDashboard::CloseLinkedIssueJob).to receive(:perform_later).with(error_log.id)
      described_class.on_error_resolved(error_log)
    end

    it "skips when no linked issue" do
      expect(RailsErrorDashboard::CloseLinkedIssueJob).not_to receive(:perform_later)
      described_class.on_error_resolved(error_log)
    end
  end

  describe ".on_error_reopened" do
    it "enqueues ReopenLinkedIssueJob when issue is linked" do
      error_log.update!(external_issue_url: "https://github.com/user/repo/issues/42")
      expect(RailsErrorDashboard::ReopenLinkedIssueJob).to receive(:perform_later).with(error_log.id)
      described_class.on_error_reopened(error_log)
    end
  end

  describe ".on_error_recurred" do
    it "enqueues AddIssueRecurrenceCommentJob when issue is linked" do
      error_log.update!(external_issue_url: "https://github.com/user/repo/issues/42")
      expect(RailsErrorDashboard::AddIssueRecurrenceCommentJob).to receive(:perform_later).with(error_log.id)
      described_class.on_error_recurred(error_log)
    end
  end

  # A duplicate group is linked to the issue its sibling already has rather
  # than opening a second one. The repository is half the issue's identity:
  # copying url + number without it made every later API call (comment, close,
  # reopen) go to the CONFIGURED repository's issue with that number.
  describe "linking a duplicate to its sibling's issue" do
    let!(:sibling) do
      create(:error_log, error_hash: "dedup_hash_1", occurred_at: 2.days.ago).tap do |row|
        row.update_columns(
          external_issue_url: "https://github.com/acme/web/issues/42", external_issue_number: 42,
          external_issue_provider: "github", external_issue_repo: "acme/web"
        )
      end
    end
    let(:duplicate) do
      create(:error_log, application: sibling.application, occurred_at: 1.minute.ago).tap do |row|
        row.update_columns(error_hash: "dedup_hash_1")
      end
    end

    before { RailsErrorDashboard.configuration.issue_tracker_repo = "acme/api" }

    it "copies the repository along with url, number and provider, and creates no issue" do
      described_class.on_error_logged(duplicate)

      duplicate.reload
      expect(duplicate.external_issue_url).to eq("https://github.com/acme/web/issues/42")
      expect(duplicate.external_issue_number).to eq(42)
      expect(duplicate.external_issue_provider).to eq("github")
      expect(duplicate.external_issue_repo).to eq("acme/web")
      expect(RailsErrorDashboard::CreateIssueJob).not_to have_been_enqueued
    end

    it "makes the API client for the duplicate target the sibling's repository" do
      described_class.on_error_logged(duplicate)

      client = RailsErrorDashboard::Services::IssueTrackerClient.for_error(duplicate.reload)
      expect(client.instance_variable_get(:@repo)).to eq("acme/web")
    end

    it "still links when the repo column has not been migrated yet" do
      columns = RailsErrorDashboard::ErrorLog.column_names - [ "external_issue_repo" ]
      allow(RailsErrorDashboard::ErrorLog).to receive(:column_names).and_return(columns)

      expect { described_class.on_error_logged(duplicate) }.not_to raise_error
      expect(duplicate.reload.external_issue_number).to eq(42)
    end
  end

  describe "safety" do
    it "never raises on nil error_log" do
      expect { described_class.on_error_logged(nil) }.not_to raise_error
      expect { described_class.on_error_resolved(nil) }.not_to raise_error
      expect { described_class.on_error_reopened(nil) }.not_to raise_error
      expect { described_class.on_error_recurred(nil) }.not_to raise_error
    end
  end
end
