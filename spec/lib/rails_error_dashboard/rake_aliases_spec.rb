# frozen_string_literal: true

require "rails_helper"
require "rake"

# Decision 0008: one namespace, and the old names keep working until 2.0, because
# a crontab calling one must not quietly stop. Each spy stands in for the task's
# body, which needs its own setup and has its own spec.
RSpec.describe "The old rake task names" do
  names = %w[
    verify list_applications backfill_application app_stats cleanup_resolved diagnostic_dump
    retention_cleanup scrub_invalid_encoding backfill_resolved_at digest_session_ids send_digest
  ]

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("rails_error_dashboard:verify") }

  after { RailsErrorDashboard::Deprecation.reset! }

  names.each do |name|
    describe name do
      let(:old_task) { Rake::Task["error_dashboard:#{name}"] }
      let(:new_task) { Rake::Task["rails_error_dashboard:#{name}"] }

      before do
        old_task.reenable
        allow(new_task).to receive(:invoke)
      end

      after { old_task.reenable }

      it "warns on standard error, naming the new task (deprecations-0-18/REQ-11)" do
        expect { old_task.invoke }
          .to output(/\[Rails Error Dashboard\] DEPRECATION: .*error_dashboard:#{name} .*rails_error_dashboard:#{name}.*2\.0/).to_stderr
      end

      it "runs the new task once (deprecations-0-18/REQ-11)" do
        silence_stderr { old_task.invoke }

        expect(new_task).to have_received(:invoke).once
      end

      it "lets the new task's error through, so the exit status survives (deprecations-0-18/REQ-11)" do
        allow(new_task).to receive(:invoke).and_raise(RuntimeError, "boom")

        expect { silence_stderr { old_task.invoke } }.to raise_error(RuntimeError, "boom")
      end
    end
  end

  it "lists every task under the new name, and no old name, in rake -T (deprecations-0-18/REQ-10)" do
    expect(listed_tasks).to match_array(names.map { |name| "rails_error_dashboard:#{name}" })
  end

  it "leaves ENV as the caller set it, which is how these tasks take input (deprecations-0-18/REQ-11)" do
    old_task = Rake::Task["error_dashboard:send_digest"]
    new_task = Rake::Task["rails_error_dashboard:send_digest"]
    old_task.reenable
    seen = nil
    allow(new_task).to receive(:invoke) { seen = ENV["PERIOD"] }

    with_env("PERIOD" => "weekly") { silence_stderr { old_task.invoke } }

    expect(seen).to eq("weekly")
  ensure
    old_task.reenable
  end

  it "really runs a task end to end through the old name (deprecations-0-18/REQ-11)" do
    old_task = Rake::Task["error_dashboard:list_applications"]
    new_task = Rake::Task["rails_error_dashboard:list_applications"]
    [ old_task, new_task ].each(&:reenable)
    create(:application, name: "Through the alias")

    expect { silence_stderr { old_task.invoke } }.to output(/Through the alias/).to_stdout
  ensure
    [ old_task, new_task ].each(&:reenable)
  end

  # What rake -T shows. Rake only keeps descriptions when it's told to, which the
  # suite's tasks weren't, so this loads the file into a Rake of its own.
  def listed_tasks
    original = Rake.application
    recording = Rake::TaskManager.record_task_metadata
    Rake.application = Rake::Application.new
    Rake::TaskManager.record_task_metadata = true
    load RailsErrorDashboard::Engine.root.join("lib/tasks/error_dashboard.rake").to_s
    Rake.application.tasks.select(&:comment).map(&:name)
  ensure
    Rake.application = original
    Rake::TaskManager.record_task_metadata = recording
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  def with_env(values)
    saved = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
