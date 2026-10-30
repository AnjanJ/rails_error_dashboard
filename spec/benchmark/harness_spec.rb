# frozen_string_literal: true

require "rails_helper"
require "open3"
require_relative "../../benchmark/harness"

RSpec.describe "bin/benchmark harness" do
  root = File.expand_path("../..", __dir__)

  # One boot of the real script, shared by the examples below: it takes a few
  # seconds. RUBYOPT keeps the parent's (bundle exec puts bundler/setup there)
  # and adds WebMock with every connection refused, so a network call anywhere
  # in the boot fails the run.
  before(:all) do
    env = {
      "RUBYOPT" => "#{ENV['RUBYOPT']} -r#{File.join(root, 'spec/benchmark/offline.rb')}".strip,
      "RAILS_ENV" => nil,
      "DATABASE_URL" => nil
    }
    @output, @errors, @status = Open3.capture3(env, "ruby", File.join(root, "bin/benchmark"), "--list", chdir: root)
    @facts = @output.lines.filter_map { |line| line.chomp.split(": ", 2) if line.include?(": ") }.to_h
  end

  it "boots without touching the network (overhead-benchmark/REQ-1)" do
    expect(@status).to be_success, "bin/benchmark --list failed:\n#{@errors}"
  end

  it "runs the dummy app like production: eager loading on, reloading off (overhead-benchmark/REQ-5)" do
    expect(@facts["Eager loading"]).to eq("on")
    expect(@facts["Code reloading"]).to eq("off")
  end

  it "uses a scratch database under tmp/, never the suite's (overhead-benchmark/REQ-1)" do
    database = @facts.fetch("Scratch database")

    expect(database).to start_with(File.join(root, "tmp", ""))
    expect(database).not_to end_with("spec/dummy/db/test.sqlite3")
  end

  it "enqueues jobs into an adapter that drops them (overhead-benchmark/REQ-1)" do
    expect(@facts["Job adapter"]).to eq("RedBenchmark::NullJobAdapter")
  end

  it "records the environment the numbers came from (overhead-benchmark/REQ-6)" do
    expect(@facts["Ruby"]).to eq(RUBY_VERSION)
    expect(@facts["Rails"]).to eq(Rails.version)
    expect(@facts["Database"]).to eq("sqlite3")
    expect(@facts["CPU"]).to be_present
    expect(Integer(@facts["CPUs"])).to be_positive
    expect(@facts["OS"]).to be_present
    expect(@facts["RED commit"]).to match(/\A\h{7,}\z/)
  end

  describe RedBenchmark::NullJobAdapter do
    it "serialises each job, as a real backend does, and never runs it (overhead-benchmark/REQ-1)" do
      job = RailsErrorDashboard::AsyncErrorLoggingJob.new({ "class_name" => "RuntimeError" }, {})
      allow(job).to receive(:serialize).and_call_original
      expect(job).not_to receive(:perform_now)

      described_class.new.enqueue(job)
      described_class.new.enqueue_at(job, Time.now.to_f + 60)

      expect(job).to have_received(:serialize).twice
    end
  end
end
