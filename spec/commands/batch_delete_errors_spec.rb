# frozen_string_literal: true

require "rails_helper"

# A batch delete removes the errors and everything that references them, in
# batches and without loading each row, then tells the plugins which ids went.
RSpec.describe RailsErrorDashboard::Commands::BatchDeleteErrors, "deleting in batches" do
  let(:logs) { RailsErrorDashboard::ErrorLog }

  def error_with_dependents
    error = create(:error_log)
    occurrence = create(:error_occurrence, error_log: error)
    RailsErrorDashboard::ErrorOccurrenceContext.create!(error_occurrence: occurrence, error_log: error, system_health: "{}",
                                                        created_at: Time.current)
    RailsErrorDashboard::ErrorComment.create!(error_log: error, author_name: "Ops", body: "Looking into it")
    RailsErrorDashboard::EventCount.create!(error_log_id: error.id, count: 2,
                                            bucket_at: RailsErrorDashboard::EventCount.bucket_for(Time.current))
    error
  end

  def dependents_of(ids)
    patterns = RailsErrorDashboard::CascadePattern
    {
      occurrences: RailsErrorDashboard::ErrorOccurrence.where(error_log_id: ids).count,
      contexts: RailsErrorDashboard::ErrorOccurrenceContext.where(error_log_id: ids).count,
      comments: RailsErrorDashboard::ErrorComment.where(error_log_id: ids).count,
      event_counts: RailsErrorDashboard::EventCount.where(error_log_id: ids).count,
      cascade_patterns: patterns.where(parent_error_id: ids).or(patterns.where(child_error_id: ids)).count
    }
  end

  it "deletes the errors and their occurrences, contexts, comments, cascade patterns and event counts (hardening-1-0-rc2/REQ-27)" do
    first, second, kept = Array.new(3) { error_with_dependents }
    create(:cascade_pattern, parent_error: first, child_error: second)
    create(:cascade_pattern, parent_error: kept, child_error: first)
    create(:cascade_pattern, parent_error: kept, child_error: create(:error_log))
    ids = [ first.id, second.id ]

    result = described_class.call(ids)

    expect(result).to include(success: true, count: 2, total: 2)
    expect(logs.where(id: ids)).to be_empty
    expect(dependents_of(ids)).to eq(occurrences: 0, contexts: 0, comments: 0, event_counts: 0, cascade_patterns: 0)
    expect(dependents_of([ kept.id ])).to eq(occurrences: 1, contexts: 1, comments: 1, event_counts: 1, cascade_patterns: 1)
  end

  it "loads none of the rows it deletes (hardening-1-0-rc2/REQ-27)" do
    ids = Array.new(3) { error_with_dependents.id }
    create(:cascade_pattern, parent_error_id: ids[0], child_error_id: ids[1])
    loaded = []
    callback = ->(*, payload) { loaded << payload[:class_name] }

    ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") { described_class.call(ids) }

    expect(logs.where(id: ids)).to be_empty
    expect(loaded.grep(/\ARailsErrorDashboard::/)).to be_empty
  end

  it "deletes 1,000 errors at a time (hardening-1-0-rc2/REQ-27)" do
    template = create(:error_log).attributes.except("id")
    logs.insert_all(Array.new(1_000) { |i| template.merge("error_hash" => format("%016x", i + 1)) })
    ids = logs.pluck(:id)
    deletes = []
    callback = lambda do |*, payload|
      deletes << payload[:sql] if payload[:sql].match?(/\ADELETE FROM [`"]?#{logs.table_name}[`"]? /i)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.call(ids) }

    expect(ids.size).to eq(1_001)
    expect(logs.count).to eq(0)
    expect(deletes.size).to eq(2)
  end

  it "dispatches on_errors_batch_deleted with the ids it deleted (hardening-1-0-rc2/REQ-28)" do
    ids = Array.new(2) { error_with_dependents.id }
    dispatched = []
    allow(RailsErrorDashboard::PluginRegistry).to receive(:dispatch) { |event, payload| dispatched << [ event, payload ] }

    described_class.call(ids + [ 0 ])

    expect(dispatched.map(&:first)).to eq([ :on_errors_batch_deleted ])
    expect(dispatched.first.last).to match_array(ids)
  end
end
