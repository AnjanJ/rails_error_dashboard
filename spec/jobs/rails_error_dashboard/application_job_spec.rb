# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ApplicationJob do
  # These two helpers decide whether a capture was handed off or silently
  # dropped. Both the ordinary async capture path (Commands::LogError) and the
  # storm flush (StormProtection::Gate) branch on them, so they are unit-tested
  # here rather than only through those callers.
  describe ".enqueued?" do
    it "is false when perform_later returned nil" do
      expect(described_class.enqueued?(nil)).to be(false)
    end

    it "is false when perform_later returned false (Rails 7.2+ swallowed EnqueueError)" do
      expect(described_class.enqueued?(false)).to be(false)
    end

    it "is false when the job reports it was not successfully enqueued" do
      job = double("job", successfully_enqueued?: false)

      expect(described_class.enqueued?(job)).to be(false)
    end

    it "is true when the job reports a successful enqueue" do
      job = double("job", successfully_enqueued?: true)

      expect(described_class.enqueued?(job)).to be(true)
    end

    it "assumes success for a job object that predates successfully_enqueued?" do
      # Rails 7.0/7.1 let ActiveJob::EnqueueError propagate instead of
      # reporting it on the job, so the caller's rescue is what catches it.
      expect(described_class.enqueued?(Object.new)).to be(true)
    end
  end

  describe ".enqueue_failure_reason" do
    it "prefers the adapter's own enqueue_error message" do
      job = double("job", enqueue_error: ActiveJob::EnqueueError.new("queue store down"))

      expect(described_class.enqueue_failure_reason(job)).to eq("queue store down")
    end

    it "describes the falsy return when there is no enqueue_error to report" do
      expect(described_class.enqueue_failure_reason(false)).to eq("perform_later returned false")
    end

    it "describes the return value when enqueue_error is nil" do
      job = double("job", enqueue_error: nil, inspect: "#<Job>")

      expect(described_class.enqueue_failure_reason(job)).to eq("perform_later returned #<Job>")
    end
  end
end
