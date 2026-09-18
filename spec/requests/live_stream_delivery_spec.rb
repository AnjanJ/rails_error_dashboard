# frozen_string_literal: true

require "rails_helper"

# Delivery, not just naming.
#
# live_stream_scoping_spec proves which streams a page SUBSCRIBES to, and the
# broadcaster spec proves which streams the broadcaster PUBLISHES to -- but the
# latter stubs Turbo::StreamsChannel, so neither of them proves that a message
# published for one application actually reaches a subscriber of that
# application's stream and no other. That is the two-tab question (M-8): with a
# global tab and an application-filtered tab open, each must see only its own
# rows.
#
# Here the messages travel through a real ActionCable subscription adapter, so
# the whole path is exercised: broadcaster -> Turbo -> pubsub -> subscriber.
RSpec.describe "Live stream delivery", type: :request do
  let(:broadcaster) { RailsErrorDashboard::Services::ErrorBroadcaster }

  # The dummy app has no cable.yml, so ActionCable.server.pubsub raises and the
  # broadcaster (correctly) reports itself unavailable. The async adapter is
  # in-process and needs no server, which is exactly what a two-tab check wants.
  before do
    skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

    @original_cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.instance_variable_set(:@pubsub, nil)

    broadcaster.instance_variable_set(:@broadcast_unavailable_until, nil)
    broadcaster.reset_throttle!
  end

  after do
    ActionCable.server.config.cable = @original_cable
    ActionCable.server.instance_variable_set(:@pubsub, nil)
    broadcaster.reset_throttle!
  end

  # The async adapter subscribes and delivers on its own thread, so both the
  # subscribe and the broadcast need a moment to land. Polls instead of
  # sleeping a fixed time so a slow machine does not make this flaky.
  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.05 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  it "delivers a row to the global and owning-application streams, and to no other application" do
    app_a = create(:application, name: "DeliveryAppA")
    app_b = create(:application, name: "DeliveryAppB")

    received = Hash.new { |hash, key| hash[key] = [] }
    pubsub = ActionCable.server.pubsub
    confirmed = []

    streams = [
      "error_list",
      "error_list_app_#{app_a.id}",
      "error_list_app_#{app_b.id}"
    ]
    streams.each do |stream|
      pubsub.subscribe(stream, ->(message) { received[stream] << message },
        -> { confirmed << stream })
    end
    wait_until { confirmed.size == streams.size }

    # Built before the count is taken: creating the row broadcasts by itself
    # (after_create_commit), and that broadcast is not the one under test.
    row = create(:error_log, application: app_a)
    wait_until { received["error_list"].any? }
    # Plain Hash with a 0 default: a stream that has received nothing yet must
    # read as 0 here, not nil.
    baseline = Hash.new(0).merge(streams.to_h { |stream| [ stream, received[stream].size ] })

    broadcaster.broadcast_new(row)
    wait_until { received["error_list"].size > baseline["error_list"] }

    delivered = ->(stream) { received[stream].size - baseline[stream] }

    aggregate_failures do
      expect(delivered.call("error_list")).to eq(1)
      expect(delivered.call("error_list_app_#{app_a.id}")).to eq(1)
      expect(delivered.call("error_list_app_#{app_b.id}")).to eq(0)
    end

    # The payload is the row itself, not a bare notification: a tab that
    # receives it has everything it needs to prepend.
    expect(received["error_list_app_#{app_a.id}"].last.to_s).to include("error_#{row.id}")
  end

  it "delivers application-scoped stats to that application's stream only" do
    app_a = create(:application, name: "StatsAppA")
    app_b = create(:application, name: "StatsAppB")
    row = create(:error_log, application: app_a)

    received = Hash.new { |hash, key| hash[key] = [] }
    pubsub = ActionCable.server.pubsub
    confirmed = []

    streams = [ "error_stats", "error_stats_app_#{app_a.id}", "error_stats_app_#{app_b.id}" ]
    streams.each do |stream|
      pubsub.subscribe(stream, ->(message) { received[stream] << message },
        -> { confirmed << stream })
    end
    wait_until { confirmed.size == streams.size }

    # One event computes at most one payload, so the global and the scoped
    # stream are served by two events -- never by one, and never app_b.
    broadcaster.reset_throttle!
    broadcaster.broadcast_stats(app_a.id)
    wait_until { received["error_stats"].any? }
    broadcaster.broadcast_stats(app_a.id)
    wait_until { received["error_stats_app_#{app_a.id}"].any? }

    aggregate_failures do
      expect(received["error_stats"].size).to eq(1)
      expect(received["error_stats_app_#{app_a.id}"].size).to eq(1)
      expect(received["error_stats_app_#{app_b.id}"]).to be_empty
    end

    expect(row.reload.application_id).to eq(app_a.id)
  end
end
