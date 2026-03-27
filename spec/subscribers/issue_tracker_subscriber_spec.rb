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

  describe "safety" do
    it "never raises on nil error_log" do
      expect { described_class.on_error_logged(nil) }.not_to raise_error
      expect { described_class.on_error_resolved(nil) }.not_to raise_error
      expect { described_class.on_error_reopened(nil) }.not_to raise_error
      expect { described_class.on_error_recurred(nil) }.not_to raise_error
    end
  end
end
