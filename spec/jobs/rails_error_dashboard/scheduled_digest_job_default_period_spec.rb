# frozen_string_literal: true

require "rails_helper"

# config.digest_frequency was shown on the Settings page and read by nothing:
# the period came only from the job argument or the rake task's PERIOD.
RSpec.describe RailsErrorDashboard::ScheduledDigestJob, "default period", type: :job do
  before do
    RailsErrorDashboard.configuration.enable_scheduled_digests = true
    RailsErrorDashboard.configuration.digest_recipients = [ "ops@example.com" ]
    allow(RailsErrorDashboard::DigestMailer).to receive(:digest_summary).and_return(double(deliver_now: true))
  end

  after { RailsErrorDashboard.reset_configuration! }

  it "takes the period from config.digest_frequency when none is given" do
    RailsErrorDashboard.configuration.digest_frequency = :weekly
    expect(RailsErrorDashboard::Services::DigestBuilder).to receive(:call).with(hash_including(period: :weekly)).and_call_original

    described_class.perform_now
  end

  it "prefers an explicit period argument" do
    RailsErrorDashboard.configuration.digest_frequency = :weekly
    expect(RailsErrorDashboard::Services::DigestBuilder).to receive(:call).with(hash_including(period: :daily)).and_call_original

    described_class.perform_now(period: "daily")
  end
end
