# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "yaml"

# The load test's traffic: benchmark/load/traffic.js, which compose.yml's k6
# service runs. The first examples read the script. The group after them runs it
# against the booted app, which needs Docker, so it runs only when asked:
#
#   LOAD_APP_BOOT=1 bundle exec rspec spec/benchmark/load_traffic_spec.rb
RSpec.describe "the load test's traffic" do
  load_folder = File.expand_path("../../benchmark/load", __dir__)

  let(:script) { File.read(File.join(load_folder, "traffic.js")) }
  let(:k6) { YAML.load_file(File.join(load_folder, "compose.yml")).dig("services", "k6") }

  it "starts requests at a fixed rate, whatever the response times (deploy-shape-benchmark/REQ-9)" do
    expect(script).to include('executor: "constant-arrival-rate"', "rate: RATE,", 'timeUnit: "1s"')
  end

  it "runs k6 from its own image, pinned by digest, only when asked (deploy-shape-benchmark/REQ-9)" do
    expect(k6["image"]).to match(%r{\Agrafana/k6:[\d.]+@sha256:\h{64}\z})
    expect(k6["profiles"]).to eq([ "load" ])
    expect(k6["volumes"]).to include("./traffic.js:/scripts/traffic.js:ro")
  end

  it "has three mixes: all healthy, one request in a hundred failing, and all failing (deploy-shape-benchmark/REQ-12)" do
    expect(script).to include("{ healthy: 0, failing: 100, storm: 1 }[MIX]", "/orders/42/charge", "/orders/42`")
  end

  describe "run against the app", if: ENV["LOAD_APP_BOOT"] == "1" do
    before(:all) { run!(*compose, "up", "--build", "--wait", "--wait-timeout", "300") }
    after(:all) { system(*compose, "down", "--volumes", out: File::NULL, err: File::NULL) }

    # k6 starts one request at each end of the duration, so 50 a second for 4 s
    # is 200 or 201 requests.
    it "sends each mix's share of failing requests, and gets the status each expects (deploy-shape-benchmark/REQ-12)" do
      %w[healthy failing storm].each do |mix|
        summary = k6_run(mix: mix, rate: 50, duration: "4s")
        total = count(summary, "iterations")
        failing = { "healthy" => 0, "failing" => (total + 99) / 100, "storm" => total }.fetch(mix)

        expect(total).to be_between(200, 201), mix
        expect([ count(summary, "http_reqs{kind:failing}"), count(summary, "http_reqs{kind:healthy}") ])
          .to eq([ failing, total - failing ]), mix
        expect(summary.dig("metrics", "http_req_failed", "values", "rate")).to eq(0), mix
      end
    end

    # Warmed first, because a cold app opening its database connections through
    # the delay falls behind. 10 a second is well within the slowed app's
    # capacity, and twice what a closed model reaches: one user waiting on each
    # response sent about 70 requests in these 15 s when it was tried.
    it "keeps its arrival rate when the app is slowed (deploy-shape-benchmark/REQ-9)" do
      k6_run(mix: "healthy", rate: 10, duration: "3s")
      delay_app(100)
      summary = k6_run(mix: "healthy", rate: 10, duration: "15s")

      expect(summary.dig("metrics", "http_req_duration", "values", "med")).to be > 100
      expect(count(summary, "iterations")).to be_between(150, 151)
      expect(count(summary, "dropped_iterations")).to eq(0)
    ensure
      remove_delay
    end

    def compose
      [ "docker", "compose", "--file", File.expand_path("../../benchmark/load/compose.yml", __dir__) ]
    end

    def run!(*command)
      output, errors, status = Open3.capture3(*command)
      raise "#{command.join(" ")} failed:\n#{errors}#{output}" unless status.success?

      output
    end

    # The script's handleSummary prints the summary as JSON on stdout.
    def k6_run(mix:, rate:, duration:)
      output = run!(*compose, "run", "--rm", "--env", "MIX=#{mix}", "--env", "RATE=#{rate}", "--env", "DURATION=#{duration}",
        "k6", "run", "--quiet", "/scripts/traffic.js")
      JSON.parse(output[output.index("{")..])
    end

    def count(summary, metric)
      summary.dig("metrics", metric, "values", "count") || 0
    end

    # Adds a delay to everything the app sends, with tc netem in a container
    # sharing its network, the way benchmark/load/probe.sh tries it.
    def delay_app(milliseconds)
      run!(*netem("add dev eth0 root netem delay #{milliseconds}ms"))
    end

    # Quietly, so a failure here can't hide the example's own.
    def remove_delay
      system(*netem("del dev eth0 root"), out: File::NULL, err: File::NULL)
    end

    def netem(change)
      app = run!(*compose, "ps", "--quiet", "app").strip
      [ "docker", "run", "--rm", "--network", "container:#{app}", "--cap-add", "NET_ADMIN", "alpine:3.20",
        "sh", "-c", "apk add --no-cache --quiet iproute2 && tc qdisc #{change}" ]
    end
  end
end
