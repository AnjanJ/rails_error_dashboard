# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-12: a single mute with a reason leaves a comment in
# the error's thread; muting the same errors in bulk left none, so the reason
# was only in muted_reason.
RSpec.describe RailsErrorDashboard::Commands::BatchMuteErrors do
  let(:errors) { create_list(:error_log, 2) }

  it "adds the single mute's comment to each error when there is a reason" do
    described_class.call(errors.map(&:id), muted_by: "ops", reason: "noisy deploy")

    errors.each do |error|
      comments = error.reload.comments.map { |c| [ c.author_name, c.body ] }
      expect(comments).to eq([ [ "ops", "Muted notifications: noisy deploy" ] ])
    end
  end

  it "adds no comment without a reason" do
    described_class.call(errors.map(&:id), muted_by: "ops")

    expect(errors.sum { |error| error.reload.comments.count }).to eq(0)
  end
end
