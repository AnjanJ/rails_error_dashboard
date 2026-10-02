# frozen_string_literal: true

require "rails_helper"
require "rake"

# Run from cron or a CI step, these tasks have no terminal: $stdin.gets returns
# nil at end of input. They called .chomp on it and crashed with NoMethodError
# instead of treating the missing answer as "no".
RSpec.describe "rake task confirmation prompts with a closed stdin" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("error_dashboard:retention_cleanup")
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    allow($stdin).to receive(:gets).and_return(nil)
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
  end

  it "error_dashboard:retention_cleanup treats no answer as no" do
    expired = create(:error_log, last_seen_at: 200.days.ago, occurred_at: 200.days.ago)

    output = nil
    expect { output = run_task("error_dashboard:retention_cleanup") }.not_to raise_error

    expect(output).to include("Cleanup cancelled")
    expect(RailsErrorDashboard::ErrorLog.exists?(expired.id)).to be true
  end

  it "error_dashboard:backfill_application treats no answer as no" do
    allow(RailsErrorDashboard::ErrorLog).to receive(:where).and_call_original
    allow(RailsErrorDashboard::ErrorLog).to receive(:where).with(application_id: nil)
      .and_return(instance_double(ActiveRecord::Relation, count: 1))

    output = nil
    expect { output = run_task("error_dashboard:backfill_application") }.not_to raise_error

    expect(output).to include("Backfill cancelled")
  end
end
