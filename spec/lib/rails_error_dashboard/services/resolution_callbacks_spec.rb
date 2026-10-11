# frozen_string_literal: true

require "rails_helper"

# Only ResolveError used to run the host's error_resolved callbacks and emit
# the instrumentation event. An error resolved from the batch toolbar or the
# status dropdown stayed resolved on the dashboard with its linked issue open.
RSpec.describe RailsErrorDashboard::Services::ResolutionCallbacks do
  let(:config) { RailsErrorDashboard.configuration }
  let(:seen) { [] }
  let(:events) { [] }

  before do
    config.notification_callbacks[:error_resolved] << ->(error) { seen << error.id }
    @subscriber = ActiveSupport::Notifications.subscribe("error_resolved.rails_error_dashboard") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  after do
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    RailsErrorDashboard.reset_configuration!
  end

  describe ".call" do
    it "runs every error_resolved callback and emits the event with the resolver" do
      error = create(:error_log, resolved: true, resolved_at: Time.current)

      described_class.call(error, resolved_by: "frodo")

      expect(seen).to eq([ error.id ])
      expect(events.size).to eq(1)
      expect(events.first.payload).to include(error_id: error.id, error_type: error.error_type, resolved_by: "frodo")
    end

    it "keeps going when one callback raises, and logs it" do
      config.notification_callbacks[:error_resolved].unshift(->(_e) { raise "hook down" })
      allow(RailsErrorDashboard::Logger).to receive(:error)
      error = create(:error_log)

      expect { described_class.call(error) }.not_to raise_error

      expect(seen).to eq([ error.id ])
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/hook down/)
    end
  end

  describe "the commands that resolve" do
    let(:error) { create(:error_log, external_issue_url: "https://github.com/o/r/issues/1") }

    before do
      config.enable_issue_tracking = true
      config.issue_tracker_provider = :github
      config.issue_tracker_repo = "o/r"
      config.issue_tracker_token = "ghp_x"
      # The real integration registers this callback at boot (engine.rb).
      config.notification_callbacks[:error_resolved] << ->(e) {
        RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_resolved(e)
      }
    end

    it "BatchResolveErrors closes each linked issue, like ResolveError does" do
      other = create(:error_log, external_issue_url: "https://github.com/o/r/issues/2")

      expect {
        RailsErrorDashboard::Commands::BatchResolveErrors.call([ error.id, other.id ], resolved_by_name: "sam")
      }.to have_enqueued_job(RailsErrorDashboard::CloseLinkedIssueJob).exactly(2).times

      expect(seen).to contain_exactly(error.id, other.id)
      expect(events.map { |e| e.payload[:resolved_by] }).to eq(%w[sam sam])
    end

    it "UpdateErrorStatus to resolved closes the linked issue" do
      error.update!(status: "in_progress")

      expect {
        RailsErrorDashboard::Commands::UpdateErrorStatus.call(error.id, status: "resolved")
      }.to have_enqueued_job(RailsErrorDashboard::CloseLinkedIssueJob).once

      expect(events.size).to eq(1)
    end

    it "UpdateErrorStatus to anything else fires nothing" do
      expect {
        RailsErrorDashboard::Commands::UpdateErrorStatus.call(error.id, status: "investigating")
      }.not_to have_enqueued_job(RailsErrorDashboard::CloseLinkedIssueJob)

      expect(events).to be_empty
    end
  end
end
