# frozen_string_literal: true

require "rails_helper"
require "rake"

# Opt-in occurrence retention: the retention job deletes a live group's old
# occurrences and their contexts, in batches, and keeps the group's counts and
# the dashboard's window counts as they were.
RSpec.describe "Occurrence retention" do
  let(:config) { RailsErrorDashboard.configuration }
  let(:job) { RailsErrorDashboard::RetentionCleanupJob }
  let(:occurrences) { RailsErrorDashboard::ErrorOccurrence }
  let(:contexts) { RailsErrorDashboard::ErrorOccurrenceContext }
  let(:volume) { RailsErrorDashboard::Queries::EventVolume }

  before do
    config.async_logging = false
    config.retention_days = 90
  end

  after { RailsErrorDashboard.reset_configuration! }

  # A group last seen ages.min days ago, with one occurrence and one stored
  # context at each age in days.
  def live_group(ages:, first_seen: nil)
    first = first_seen || ages.max.days.ago
    error = create(:error_log, occurred_at: first, first_seen_at: first, last_seen_at: ages.min.days.ago,
                               occurrence_count: ages.size)
    ages.each do |age|
      occurrence = occurrences.create!(error_log: error, occurred_at: age.days.ago)
      contexts.create!(error_occurrence: occurrence, error_log: error, system_health: "{}", created_at: age.days.ago)
    end
    error
  end

  def ages_of(error)
    occurrences.where(error_log_id: error.id).pluck(:occurred_at).map { |at| ((Time.current - at) / 1.day).round }.sort
  end

  def deletes_from(table)
    statements = []
    callback = lambda do |*, payload|
      statements << payload[:sql] if payload[:sql].match?(/\ADELETE FROM [`"]?#{table}[`"]? /i)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  describe "with occurrence_retention_days set" do
    before { config.occurrence_retention_days = 30 }

    it "deletes a live group's occurrences older than that, with their contexts, and keeps the rest (hardening-1-0-rc2/REQ-23)" do
      error = live_group(ages: [ 31, 29, 1 ])
      old = occurrences.find_by!(error_log_id: error.id, occurred_at: ..30.days.ago)

      job.new.perform

      expect(ages_of(error)).to eq([ 1, 29 ])
      expect(contexts.where(error_occurrence_id: old.id)).to be_empty
      expect(contexts.where(error_log_id: error.id).count).to eq(2)
      expect(RailsErrorDashboard::ErrorLog.exists?(error.id)).to be true
    end

    it "deletes them 1,000 at a time (hardening-1-0-rc2/REQ-23)" do
      error = live_group(ages: [ 1 ])
      now = Time.current
      occurrences.insert_all(Array.new(1_001) { { error_log_id: error.id, occurred_at: 40.days.ago, created_at: now, updated_at: now } })

      statements = deletes_from(occurrences.table_name) { job.new.perform }

      expect(statements.size).to eq(2)
      expect(ages_of(error)).to eq([ 1 ])
    end

    it "deletes them when retention_days is nil too (hardening-1-0-rc2/REQ-23)" do
      config.retention_days = nil
      error = live_group(ages: [ 400, 31, 1 ])

      job.new.perform

      expect(ages_of(error)).to eq([ 1 ])
    end

    it "leaves the group's occurrence_count, first_seen_at and last_seen_at as they were (hardening-1-0-rc2/REQ-25)" do
      error = live_group(ages: [ 60, 45, 31, 2 ])
      before = error.reload.attributes.slice("occurrence_count", "first_seen_at", "last_seen_at")

      job.new.perform

      expect(ages_of(error)).to eq([ 2 ])
      expect(error.reload.attributes.slice("occurrence_count", "first_seen_at", "last_seen_at")).to eq(before)
    end

    it "keeps every day count and window count the dashboard shows (hardening-1-0-rc2/REQ-64)" do
      config.occurrence_retention_days = 7
      # The two shapes the deletion broke: first seen before the 30-day window,
      # and first seen inside it.
      born_before = live_group(ages: [ 45, 20, 10, 2 ], first_seen: 60.days.ago)
      born_inside = live_group(ages: [ 20, 10, 2 ])
      groups = [ born_before, born_inside ].map { |error| RailsErrorDashboard::ErrorLog.where(id: error.id) }
      # The Overview's month, from a 15-minute edge, and Analytics' widest.
      month = RailsErrorDashboard::EventCount.bucket_for(30.days.ago)
      counts = lambda do
        groups.map do |scope|
          [ volume.in_window(scope, month), volume.by_day(scope, month), volume.in_window(scope, 365.days.ago),
            volume.by_day(scope, 365.days.ago) ]
        end
      end
      before = counts.call

      job.new.perform

      expect(ages_of(born_before)).to eq([ 2 ])
      expect(ages_of(born_inside)).to eq([ 2 ])
      expect(counts.call).to eq(before)
    end

    # The first bucket write lands, the second can't.
    def fail_second_bucket
      calls = 0
      allow(RailsErrorDashboard::EventCount).to receive(:accumulate).and_wrap_original do |original, **args|
        calls += 1
        calls == 1 ? original.call(**args) : :unavailable
      end
      allow(RailsErrorDashboard::Logger).to receive(:error)
    end

    it "deletes nothing of a batch whose event buckets can't be written (hardening-1-0-rc2/REQ-64)" do
      first = live_group(ages: [ 40, 1 ])
      second = live_group(ages: [ 50, 1 ])
      fail_second_bucket

      expect { job.new.perform }.not_to raise_error

      expect(ages_of(first)).to eq([ 1, 40 ])
      expect(ages_of(second)).to eq([ 1, 50 ])
      expect(contexts.where(error_log_id: [ first.id, second.id ]).count).to eq(4)
      # The first bucket was written in the batch's transaction, and rolled back with it.
      expect(RailsErrorDashboard::EventCount.where(error_log_id: [ first.id, second.id ])).to be_empty
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/Occurrence retention/)
    end

    # perform_now from inside the host's own transaction: a plain inner
    # transaction would join it, and the batch's rollback would undo nothing.
    it "rolls a batch's bucket back inside a caller's transaction too (hardening-1-0-rc2/REQ-64)" do
      first = live_group(ages: [ 40, 1 ])
      second = live_group(ages: [ 50, 1 ])
      fail_second_bucket

      RailsErrorDashboard::ErrorLogsRecord.transaction { job.new.perform }

      expect(ages_of(first)).to eq([ 1, 40 ])
      expect(ages_of(second)).to eq([ 1, 50 ])
      expect(RailsErrorDashboard::EventCount.where(error_log_id: [ first.id, second.id ])).to be_empty
    end

    it "still expires old groups when the occurrence pass fails (hardening-1-0-rc2/REQ-23)" do
      expired = create(:error_log, occurred_at: 100.days.ago, last_seen_at: 100.days.ago)
      allow(job).to receive(:delete_old_occurrences).and_raise(ActiveRecord::StatementInvalid, "boom")
      allow(RailsErrorDashboard::Logger).to receive(:error)

      expect(job.new.perform).to eq(1)

      expect(RailsErrorDashboard::ErrorLog.exists?(expired.id)).to be false
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/Occurrence retention failed: ActiveRecord::StatementInvalid/)
    end

    it "still deletes old occurrences when group expiry fails (hardening-1-0-rc2/REQ-23)" do
      error = live_group(ages: [ 31, 1 ])
      allow(job).to receive(:expired_scope).and_raise(ActiveRecord::StatementInvalid, "boom")
      allow(RailsErrorDashboard::Logger).to receive(:error)

      expect(job.new.perform).to eq(0)

      expect(ages_of(error)).to eq([ 1 ])
    end
  end

  describe "with occurrence_retention_days nil, the default" do
    it "deletes no occurrence or context of a live group (hardening-1-0-rc2/REQ-24)" do
      expect(config.occurrence_retention_days).to be_nil
      error = live_group(ages: [ 400, 89, 31, 1 ])

      job.new.perform

      expect(ages_of(error)).to eq([ 1, 31, 89, 400 ])
      expect(contexts.where(error_log_id: error.id).count).to eq(4)
    end
  end

  describe "rails_error_dashboard:retention_cleanup" do
    before(:all) do
      Rails.application.load_tasks unless Rake::Task.task_defined?("rails_error_dashboard:retention_cleanup")
    end

    def run_task(answer)
      task = Rake::Task["rails_error_dashboard:retention_cleanup"]
      task.reenable
      allow($stdin).to receive(:gets).and_return(answer)
      original = $stdout
      $stdout = StringIO.new
      task.invoke
      $stdout.string
    ensure
      $stdout = original
    end

    it "previews the occurrences it will delete, not counting an expiring error's (hardening-1-0-rc2/REQ-23)" do
      config.occurrence_retention_days = 30
      error = live_group(ages: [ 45, 31, 1 ])
      expired = live_group(ages: [ 120, 100 ])

      output = run_task("n\n")

      expect(output).to include("Errors to delete: 1", "Occurrences to delete: 2", "Cleanup cancelled")
      expect(ages_of(error)).to eq([ 1, 31, 45 ])
      expect(RailsErrorDashboard::ErrorLog.exists?(expired.id)).to be true
    end

    it "runs with only occurrence_retention_days set (hardening-1-0-rc2/REQ-23)" do
      config.retention_days = nil
      config.occurrence_retention_days = 30
      error = live_group(ages: [ 45, 31, 1 ])

      output = run_task("y\n")

      expect(output).to include("Occurrences to delete: 2", "Deleted: 2 occurrences")
      expect(output).not_to include("retention_days is not configured")
      expect(ages_of(error)).to eq([ 1 ])
    end
  end
end
