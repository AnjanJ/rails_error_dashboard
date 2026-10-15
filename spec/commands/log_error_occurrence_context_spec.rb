# frozen_string_literal: true

require "rails_helper"

# The error row keeps only its latest capture's context (C2); each occurrence
# now keeps its own, the newest occurrence_context_limit per error.
RSpec.describe "LogError keeps each occurrence's context" do
  let(:config) { RailsErrorDashboard.configuration }
  let(:contexts) { RailsErrorDashboard::ErrorOccurrenceContext }

  around do |example|
    saved = [ config.enable_system_health, config.occurrence_context_limit, config.async_logging ]
    config.enable_system_health = true
    example.run
  ensure
    config.enable_system_health, config.occurrence_context_limit, config.async_logging = saved
  end

  # The same line every time, so every call is one error group
  def capture(context = {})
    raise ArgumentError, "occurrence context probe"
  rescue ArgumentError => e
    RailsErrorDashboard::Commands::LogError.call(e, context)
  end

  def error_log
    RailsErrorDashboard::ErrorLog.find_by!(message: "occurrence context probe")
  end

  # occurrence-context-history/REQ-1, occurrence-context-history/REQ-11
  it "stores the context the error row got, for a sync capture" do
    capture

    context = contexts.sole
    expect(context.system_health).to be_present
    expect(context.system_health).to eq(error_log.system_health)
    expect(context.error_occurrence).to eq(error_log.error_occurrences.sole)
    expect(context.error_log_id).to eq(error_log.id)
  end

  # occurrence-context-history/REQ-1, occurrence-context-history/REQ-11
  it "stores the context the error row got, for an async capture" do
    config.async_logging = true

    capture
    perform_enqueued_jobs

    expect(contexts.sole.system_health).to be_present
    expect(contexts.sole.system_health).to eq(error_log.system_health)
  end

  # occurrence-context-history/REQ-2
  it "stores nothing for a storm-protection lite capture" do
    capture(_storm_decision: :lite)

    expect(error_log.error_occurrences.count).to eq(1)
    expect(contexts.count).to eq(0)
  end

  # occurrence-context-history/REQ-2
  it "stores nothing when no context was captured" do
    config.enable_system_health = false

    capture

    expect(contexts.count).to eq(0)
  end

  # occurrence-context-history/REQ-3
  it "keeps only the newest occurrence_context_limit contexts per error" do
    config.occurrence_context_limit = 3

    5.times { capture }

    newest = error_log.error_occurrences.order(id: :desc).limit(3).pluck(:id)
    expect(contexts.where(error_log_id: error_log.id).pluck(:error_occurrence_id)).to match_array(newest)
  end

  # occurrence-context-history/REQ-4
  it "stores nothing when the limit is 0" do
    config.occurrence_context_limit = 0

    2.times { capture }

    expect(error_log.error_occurrences.count).to eq(2)
    expect(contexts.count).to eq(0)
  end

  # occurrence-context-history/REQ-10
  it "still records the error and the occurrence when storing the context fails" do
    allow(contexts).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "disk full")

    expect { capture }.not_to raise_error

    expect(error_log.error_occurrences.count).to eq(1)
    expect(contexts.count).to eq(0)
  end
end
