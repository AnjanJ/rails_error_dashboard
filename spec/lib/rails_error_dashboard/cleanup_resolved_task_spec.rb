# frozen_string_literal: true

require "rails_helper"
require "rake"

# The task deleted error logs with one unbounded delete_all and never touched
# their occurrences, comments or cascade patterns. Those rows reference the
# log through foreign keys, so the delete failed on any error that had them.
RSpec.describe "error_dashboard:cleanup_resolved rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("error_dashboard:cleanup_resolved")
  end

  let(:task) { Rake::Task["error_dashboard:cleanup_resolved"] }

  around do |example|
    original = ENV["DAYS"]
    ENV["DAYS"] = "30"
    example.run
  ensure
    original ? ENV["DAYS"] = original : ENV.delete("DAYS")
  end

  before do
    task.reenable
  end

  def run_task(confirmation)
    allow($stdin).to receive(:gets).and_return("#{confirmation}\n")
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
  end

  let!(:old_resolved) { create(:error_log, resolved: true, resolved_at: 60.days.ago) }
  let!(:recent_resolved) { create(:error_log, resolved: true, resolved_at: 1.day.ago) }

  it "deletes old resolved errors together with their occurrences, comments and cascade patterns" do
    create(:error_occurrence, error_log: old_resolved)
    create(:cascade_pattern, parent_error: old_resolved, child_error: recent_resolved)
    RailsErrorDashboard::ErrorComment.create!(error_log: old_resolved, author_name: "spec", body: "spec")

    output = run_task("y")

    expect(output).to include("Deleted: 1 errors")
    expect(RailsErrorDashboard::ErrorLog.exists?(old_resolved.id)).to be false
    expect(RailsErrorDashboard::ErrorOccurrence.where(error_log_id: old_resolved.id)).to be_empty
    expect(RailsErrorDashboard::ErrorComment.where(error_log_id: old_resolved.id)).to be_empty
    expect(RailsErrorDashboard::CascadePattern.where(parent_error_id: old_resolved.id)).to be_empty
  end

  it "keeps recent resolved errors and unresolved ones" do
    unresolved = create(:error_log, resolved: false)

    run_task("y")

    expect(RailsErrorDashboard::ErrorLog.exists?(recent_resolved.id)).to be true
    expect(RailsErrorDashboard::ErrorLog.exists?(unresolved.id)).to be true
  end

  it "deletes nothing unless confirmed" do
    output = run_task("n")

    expect(output).to include("Cleanup cancelled")
    expect(RailsErrorDashboard::ErrorLog.exists?(old_resolved.id)).to be true
  end
end
