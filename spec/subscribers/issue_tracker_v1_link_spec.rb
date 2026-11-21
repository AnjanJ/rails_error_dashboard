# frozen_string_literal: true

require "rails_helper"

# A new v2 group links to the issue its v1 group already has.
# See .shipkit/specs/hardening-1-0-rc2 (REQ-62).
#
# IssueTrackerSubscriber links a new group to an existing issue by
# error_hash. An rc.1 group the lookups no longer match (outside the 24-hour
# window) keeps its v1 hash, so its error's first v2 capture opens a new
# group, and without the v1 hash that group would get a second issue.
RSpec.describe "a new v2 group and its v1 group's issue" do
  include ActiveJob::TestHelper

  let(:generator) { RailsErrorDashboard::Services::ErrorHashGenerator }
  let(:logs) { RailsErrorDashboard::ErrorLog }
  let(:application) do
    RailsErrorDashboard::Application.find_or_create_by_name(RailsErrorDashboard.resolved_application_name)
  end
  let(:identities) { generator.identities(boom) }
  let(:v2_hash) { generator.complete(identities[:v2], application.id) }
  let(:v1_hash) { generator.complete(identities[:v1], application.id) }
  let(:issue_url) { "https://github.com/user/repo/issues/7" }

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.sampling_rate = 1.0
    config.enable_storm_protection = false
    config.enable_issue_tracking = true
    config.issue_tracker_provider = :github
    config.issue_tracker_token = "ghp_test"
    config.issue_tracker_repo = "user/repo"
    # The dispatch the engine registers when issue tracking is on at boot
    # (engine.rb), for a first occurrence.
    config.notification_callbacks[:error_logged] = [
      ->(error_log) { RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_logged(error_log) if error_log.occurrence_count == 1 }
    ]
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
    allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:issue_creation_allowed?).and_return(true)
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    RailsErrorDashboard.reset_configuration!
    RailsErrorDashboard::Services::StormProtection::Gate.reset!
  end

  def boom
    error = ArgumentError.new("widget 42 failed")
    error.set_backtrace([
      "#{Rails.root}/app/services/widget_service.rb:12:in 'explode'",
      "#{Rails.root}/app/controllers/widgets_controller.rb:5:in 'show'"
    ])
    error
  end

  # An rc.1 group with a linked issue, last seen two days ago: no lookup
  # matches it, so the next capture opens a new group.
  def seed_v1_group_with_issue
    group = logs.create!(
      application_id: application.id,
      error_type: "ArgumentError",
      message: "widget 42 failed",
      error_hash: v1_hash,
      occurred_at: 2.days.ago,
      first_seen_at: 2.days.ago,
      last_seen_at: 2.days.ago,
      occurrence_count: 3,
      resolved: false,
      status: "new",
      external_issue_url: issue_url,
      external_issue_number: 7,
      external_issue_provider: "github"
    )
    group.update_columns(external_issue_repo: "user/repo") if logs.column_names.include?("external_issue_repo")
    group
  end

  def create_issue_jobs
    enqueued_jobs.count { |job| job[:job] == RailsErrorDashboard::CreateIssueJob }
  end

  def capture_sync
    RailsErrorDashboard.configuration.async_logging = false
    RailsErrorDashboard::Commands::LogError.call(boom)
  end

  def capture_async
    RailsErrorDashboard.configuration.async_logging = true
    RailsErrorDashboard::Commands::LogError.call(boom)
    perform_enqueued_jobs(only: RailsErrorDashboard::AsyncErrorLoggingJob)
  end

  [ :sync, :async ].each do |path|
    it "links a #{path} capture's new group to the v1 group's issue (hardening-1-0-rc2/REQ-62)" do
      group = seed_v1_group_with_issue

      send(:"capture_#{path}")

      created = logs.find_by!(error_hash: v2_hash)
      expect(created.id).not_to eq(group.id)
      expect(created.external_issue_url).to eq(issue_url)
      expect(created.external_issue_number).to eq(7)
      expect(create_issue_jobs).to eq(0)
      expect(group.reload.error_hash).to eq(v1_hash)
    end
  end

  it "creates an issue as before when there is no v1 group (hardening-1-0-rc2/REQ-62)" do
    capture_sync

    expect(logs.sole.external_issue_url).to be_nil
    expect(create_issue_jobs).to eq(1)
  end

  it "never stores the v1 hash (hardening-1-0-rc2/REQ-62)" do
    created = capture_sync

    expect(created.error_hash_v1).to eq(v1_hash)
    expect(logs.column_names).not_to include("error_hash_v1")
    expect(logs.find(created.id).error_hash_v1).to be_nil
  end
end
