# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe RailsErrorDashboard::Commands::BackfillResolvedAt do
  let!(:application) { create(:application) }

  def resolved_without_timestamp(updated_at:)
    row = create(:error_log, application: application, status: "resolved")
    row.update_columns(resolved: true, resolved_at: nil, updated_at: updated_at)
    row
  end

  it "sets resolved_at to each row's own updated_at" do
    older = resolved_without_timestamp(updated_at: 5.days.ago.change(usec: 0))
    newer = resolved_without_timestamp(updated_at: 1.day.ago.change(usec: 0))

    result = described_class.call

    expect(result).to eq(updated: 2)
    expect(older.reload.resolved_at).to eq(older.updated_at)
    expect(newer.reload.resolved_at).to eq(newer.updated_at)
    expect(older.resolved_at).not_to eq(newer.resolved_at)
  end

  it "leaves updated_at alone" do
    stamp = 5.days.ago.change(usec: 0)
    row = resolved_without_timestamp(updated_at: stamp)

    described_class.call

    expect(row.reload.updated_at).to eq(stamp)
  end

  it "does not touch unresolved rows or rows that already have a resolved_at" do
    unresolved = create(:error_log, application: application)
    stamped_at = 2.days.ago.change(usec: 0)
    stamped = create(:error_log, application: application, status: "resolved")
    stamped.update_columns(resolved: true, resolved_at: stamped_at)

    result = described_class.call

    expect(result).to eq(updated: 0)
    expect(unresolved.reload.resolved_at).to be_nil
    expect(stamped.reload.resolved_at).to eq(stamped_at)
  end

  it "covers every row across batch boundaries and is idempotent" do
    5.times { resolved_without_timestamp(updated_at: 3.days.ago) }

    expect(described_class.call(batch_size: 2)).to eq(updated: 5)
    expect(described_class.call(batch_size: 2)).to eq(updated: 0)
  end

  it "makes the backfilled errors count toward MTTR" do
    row = resolved_without_timestamp(updated_at: 1.hour.ago)
    row.update_columns(occurred_at: 5.hours.ago)
    expect(RailsErrorDashboard::Queries::MttrStats.call(30)[:total_resolved]).to eq(0)

    described_class.call

    stats = RailsErrorDashboard::Queries::MttrStats.call(30)
    expect(stats[:total_resolved]).to eq(1)
    expect(stats[:overall_mttr]).to be_within(0.1).of(4.0)
  end

  describe "rake error_dashboard:backfill_resolved_at" do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("error_dashboard:backfill_resolved_at") }

    it "prints the count" do
      resolved_without_timestamp(updated_at: 1.day.ago)
      task = Rake::Task["error_dashboard:backfill_resolved_at"]
      task.reenable

      expect { task.invoke }.to output(/Backfilled resolved_at on 1 resolved error/).to_stdout
    end
  end
end
