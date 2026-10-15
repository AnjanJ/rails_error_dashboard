# frozen_string_literal: true

require "rails_helper"

# occurrence-context-history/REQ-5: an occurrence's stored context goes when its
# error does, however the error is deleted.
RSpec.describe "Deleting errors deletes their occurrence contexts" do
  let(:contexts) { RailsErrorDashboard::ErrorOccurrenceContext }

  def error_with_context(**attrs)
    error = create(:error_log, **attrs)
    occurrence = create(:error_occurrence, error_log: error)
    contexts.create!(error_occurrence: occurrence, error_log: error, system_health: "{}", created_at: Time.current)
    error
  end

  # delete_all skips the has_many :dependent callbacks, so retention and
  # error_dashboard:cleanup_resolved (which share this method) must name the table
  it "removes them in delete_with_dependents, and only for the deleted errors" do
    doomed = error_with_context
    kept = error_with_context

    RailsErrorDashboard::RetentionCleanupJob.delete_with_dependents(RailsErrorDashboard::ErrorLog.where(id: doomed.id))

    expect(contexts.where(error_log_id: doomed.id)).to be_empty
    expect(contexts.where(error_log_id: kept.id).count).to eq(1)
  end

  it "removes them when retention expires the error" do
    config = RailsErrorDashboard.configuration
    saved = config.retention_days
    config.retention_days = 30
    expired = error_with_context(occurred_at: 60.days.ago, last_seen_at: 60.days.ago)

    RailsErrorDashboard::RetentionCleanupJob.new.perform

    expect(contexts.where(error_log_id: expired.id)).to be_empty
  ensure
    config.retention_days = saved
  end

  it "removes them on a batch delete" do
    error = error_with_context

    RailsErrorDashboard::Commands::BatchDeleteErrors.call([ error.id ])

    expect(contexts.where(error_log_id: error.id)).to be_empty
  end
end
