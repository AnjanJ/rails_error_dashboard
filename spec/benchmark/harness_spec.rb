# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tempfile"
require_relative "../../benchmark/harness"
require_relative "../../benchmark/scenarios"

RSpec.describe "bin/benchmark harness" do
  root = File.expand_path("../..", __dir__)

  # Runs the real script. RUBYOPT keeps the parent's (bundle exec puts
  # bundler/setup there) and adds WebMock with every connection refused, so a
  # network call anywhere in the run fails it.
  define_method(:run_script) do |*arguments|
    env = {
      "RUBYOPT" => "#{ENV['RUBYOPT']} -r#{File.join(root, 'spec/benchmark/offline.rb')}".strip,
      "RAILS_ENV" => nil,
      "DATABASE_URL" => nil,
      "RUBY_YJIT_ENABLE" => nil
    }
    Open3.capture3(env, "ruby", File.join(root, "bin/benchmark"), *arguments, chdir: root)
  end

  # One boot of the real script, shared by the examples below: it takes a few
  # seconds.
  before(:all) do
    @output, @errors, @status = run_script("--list")
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

  it "runs with YJIT on wherever this Ruby can turn it on, and records it (overhead-benchmark/REQ-6)" do
    expect(@facts["YJIT"]).to eq(defined?(RubyVM::YJIT.enable) ? "on" : "not available")
  end

  # The whole script, every scenario, once. In a few iterations a gated row can
  # go either way, so these examples hold the script to its own table rather
  # than to the budgets.
  describe "a run with --summary" do
    before(:all) do
      @summary = Tempfile.new("red_benchmark_summary")
      @summary.write("From an earlier step\n")
      @summary.close
      @run_output, @run_errors, @run_status = run_script("--smoke", "--summary", @summary.path)
      @written = File.read(@summary.path)
    end

    after(:all) { @summary.unlink }

    it "runs every scenario without touching the network (overhead-benchmark/REQ-1)" do
      expect(@run_status.exitstatus).to be_between(0, 1), "bin/benchmark failed:\n#{@run_errors}"
      expect(@run_output).to include(*RedBenchmark::Scenarios.all.map(&:name))
    end

    it "appends the table to the summary file, after what is already there (overhead-benchmark/REQ-9)" do
      expect(@written).to start_with("From an earlier step\n")
      expect(@written).to include("| Measurement | Median | p95 | Budget | Result |")
      expect(@written).to include(*RedBenchmark::Scenarios.all.map(&:name))
    end

    it "exits non-zero exactly when its table shows a FAIL (overhead-benchmark/REQ-7)" do
      expect(@run_status.exitstatus).to eq(@run_output.include?("| FAIL |") ? 1 : 0)
    end

    it "says a smoke run's numbers mean nothing (overhead-benchmark/REQ-9)" do
      expect(@written).to include("Smoke run")
    end
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
