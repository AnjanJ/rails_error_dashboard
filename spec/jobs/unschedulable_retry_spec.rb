# frozen_string_literal: true

require "rails_helper"

# A RED job whose retry can't be scheduled ends that attempt and raises
# nothing into the code that enqueued or ran it (hardening-1-0-rc2/REQ-63).
#
# :inline, and Resque without a scheduler, Sneakers and queue_classic, raise
# NotImplementedError from enqueue_at. That is a ScriptError, so it passes
# every `rescue => e`, and under :inline a job runs inside perform_later, on
# the thread that enqueued it: for these jobs, a capture. The adapter's
# enqueue_at is stubbed, never swapped (swapping adapters leaks between
# specs), and each job runs through perform_enqueued_jobs, as :inline runs it.
RSpec.describe "A RED job's retry that can't be scheduled" do
  let(:log) { StringIO.new }
  let(:store_down) { ActiveRecord::ConnectionNotEstablished }

  around do |example|
    saved = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    example.run
  ensure
    Rails.logger = saved
  end

  after { RailsErrorDashboard.reset_configuration! }

  def unschedulable(job_class)
    allow(job_class.queue_adapter).to receive(:enqueue_at)
      .and_raise(NotImplementedError, "Use a queueing backend to enqueue jobs in the future.")
  end

  def unschedulable_lines = log.string.lines.grep(/#retry_job: NotImplementedError/)

  # The six jobs capture code enqueues that raise into retry_on, each with a
  # failure that makes it raise (design.md, the S1 decision's third amendment).
  {
    RailsErrorDashboard::CreateIssueJob => proc do |id|
      allow(RailsErrorDashboard::Commands::CreateIssue).to receive(:call).and_raise(store_down, "db down")
      RailsErrorDashboard::CreateIssueJob.perform_later(id)
    end,
    RailsErrorDashboard::ReopenLinkedIssueJob => proc do |id|
      allow(RailsErrorDashboard::ErrorLog).to receive(:find).and_raise(store_down, "db down")
      RailsErrorDashboard::ReopenLinkedIssueJob.perform_later(id)
    end,
    RailsErrorDashboard::AddIssueRecurrenceCommentJob => proc do |id|
      allow(RailsErrorDashboard::ErrorLog).to receive(:find).and_raise(store_down, "db down")
      RailsErrorDashboard::AddIssueRecurrenceCommentJob.perform_later(id)
    end,
    RailsErrorDashboard::CloseLinkedIssueJob => proc do |id|
      allow(RailsErrorDashboard::ErrorLog).to receive(:find).and_raise(store_down, "db down")
      RailsErrorDashboard::CloseLinkedIssueJob.perform_later(id)
    end,
    RailsErrorDashboard::StormFlushJob => proc do |_id|
      allow(RailsErrorDashboard::Commands::FlushStormCounts).to receive(:call).and_raise(store_down, "db down")
      RailsErrorDashboard::StormFlushJob.perform_later(entries: [], batch_id: "unschedulable-batch")
    end,
    RailsErrorDashboard::BaselineAlertJob => proc do |id|
      allow(RailsErrorDashboard::ErrorLog).to receive(:find_by).and_raise(store_down, "db down")
      RailsErrorDashboard::BaselineAlertJob.perform_later(id, { "level" => "high" }, nil)
    end
  }.each do |job_class, fail_and_enqueue|
    it "ends #{job_class.name.demodulize}'s failed attempt as its last, raising nothing, and says so (hardening-1-0-rc2/REQ-63)" do
      id = create(:error_log).id
      unschedulable(job_class)

      expect { perform_enqueued_jobs { instance_exec(id, &fail_and_enqueue) } }.not_to raise_error

      expect(job_class.queue_adapter).to have_received(:enqueue_at).once
      expect(unschedulable_lines.size).to eq(1)
      expect(unschedulable_lines.first).to include(job_class.name.delete_prefix("RailsErrorDashboard::"))
    end
  end

  job_classes = Dir[File.join(RailsErrorDashboard::Engine.root, "app/jobs/rails_error_dashboard/*_job.rb")].sort
    .map { |path| "RailsErrorDashboard::#{File.basename(path, ".rb").camelize}".constantize }
    .reject { |klass| klass == RailsErrorDashboard::ApplicationJob }

  it "reads every RED job class from app/jobs" do
    expect(job_classes.size).to be > 20
    expect(job_classes).to include(RailsErrorDashboard::AsyncErrorLoggingJob, RailsErrorDashboard::SlackErrorNotificationJob)
  end

  job_classes.each do |job_class|
    it "#{job_class.name.demodulize} ends an unschedulable retry without raising (hardening-1-0-rc2/REQ-63)" do
      unschedulable(job_class)

      expect { job_class.new.retry_job(wait: 5, error: store_down.new("db down")) }.not_to raise_error
      expect(job_class.queue_adapter).to have_received(:enqueue_at).once
    end
  end

  it "lets a sync capture whose issue job fails that way finish its later steps (hardening-1-0-rc2/REQ-63)" do
    config = RailsErrorDashboard.configuration
    config.async_logging = false
    config.enable_issue_tracking = true
    config.notification_callbacks[:error_logged] = [
      ->(error_log) { RailsErrorDashboard::Subscribers::IssueTrackerSubscriber.on_error_logged(error_log) }
    ]
    unschedulable(RailsErrorDashboard::CreateIssueJob)
    allow(RailsErrorDashboard::Commands::CreateIssue).to receive(:call).and_raise(store_down, "db down")
    events = []
    subscription = ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") { |*| events << :logged }

    result = perform_enqueued_jobs { RailsErrorDashboard::Commands::LogError.call(ArgumentError.new("issue job down"), {}) }

    expect(result).to be_a(RailsErrorDashboard::ErrorLog)
    expect(events).to eq([ :logged ])
    expect(unschedulable_lines.size).to eq(1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  it "raises nothing from the server's response-finished callback when the enqueue raises a ScriptError (hardening-1-0-rc2/REQ-63)" do
    allow(RailsErrorDashboard::Commands::LogError).to receive(:enqueue_async)
      .and_raise(NotImplementedError, "Use a queueing backend to enqueue jobs in the future.")

    expect {
      RailsErrorDashboard::Commands::LogError.enqueue_after_response(ArgumentError.new("after"), {}, {})
    }.not_to raise_error
    expect(log.string).to include("Capture failure in Commands::LogError.enqueue_after_response: NotImplementedError")
  end
end
