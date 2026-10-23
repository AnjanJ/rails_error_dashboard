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
    RailsErrorDashboard.configuration.enable_live_updates = true
  end

  after do
    RailsErrorDashboard.configuration.enable_live_updates = false
    ActionCable.server.config.cable = @original_cable
    ActionCable.server.instance_variable_set(:@pubsub, nil)
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
      "rails_error_dashboard:error_list",
      "rails_error_dashboard:error_list_app_#{app_a.id}",
      "rails_error_dashboard:error_list_app_#{app_b.id}"
    ]
    streams.each do |stream|
      pubsub.subscribe(stream, ->(message) { received[stream] << message },
        -> { confirmed << stream })
    end
    wait_until { confirmed.size == streams.size }

    # Built before the count is taken: creating the row broadcasts by itself
    # (after_create_commit), and that broadcast is not the one under test.
    row = create(:error_log, application: app_a)
    # The async adapter delivers each stream on its own schedule. Wait for the
    # create broadcast on BOTH streams that get it: a copy that reached the
    # application stream after the baseline would be counted as delivered.
    wait_until do
      received["rails_error_dashboard:error_list"].any? &&
        received["rails_error_dashboard:error_list_app_#{app_a.id}"].any?
    end
    # Plain Hash with a 0 default: a stream that has received nothing yet must
    # read as 0 here, not nil.
    baseline = Hash.new(0).merge(streams.to_h { |stream| [ stream, received[stream].size ] })

    broadcaster.broadcast_new(row)
    wait_until do
      received["rails_error_dashboard:error_list"].size > baseline["rails_error_dashboard:error_list"] &&
        received["rails_error_dashboard:error_list_app_#{app_a.id}"].size > baseline["rails_error_dashboard:error_list_app_#{app_a.id}"]
    end

    delivered = ->(stream) { received[stream].size - baseline[stream] }

    aggregate_failures do
      expect(delivered.call("rails_error_dashboard:error_list")).to eq(1)
      expect(delivered.call("rails_error_dashboard:error_list_app_#{app_a.id}")).to eq(1)
      expect(delivered.call("rails_error_dashboard:error_list_app_#{app_b.id}")).to eq(0)
    end

    # The payload is the row itself, not a bare notification: a tab that
    # receives it has everything it needs to prepend.
    expect(received["rails_error_dashboard:error_list_app_#{app_a.id}"].last.to_s).to include("error_#{row.id}")
  end

  # live-updates-hardening-0-17/REQ-4: pages served before 0.17.0 carry Turbo
  # tokens for these names that never expire. Nothing is broadcast to them.
  it "sends nothing to the stream names used before 0.17.0" do
    app = create(:application, name: "LegacyNamesApp")
    row = create(:error_log, application: app)

    received = Hash.new { |hash, key| hash[key] = [] }
    pubsub = ActionCable.server.pubsub
    confirmed = []

    legacy = %w[error_list error_updates error_stats].flat_map { |base| [ base, "#{base}_app_#{app.id}" ] }
    current = [
      broadcaster.stream_name(:list), broadcaster.stream_name(:list, app.id),
      broadcaster.stream_name(:updates), broadcaster.stream_name(:updates, app.id)
    ]
    streams = (legacy + current).uniq
    streams.each do |stream|
      pubsub.subscribe(stream, ->(message) { received[stream] << message }, -> { confirmed << stream })
    end
    wait_until { confirmed.size == streams.size }

    broadcaster.broadcast_new(row)
    broadcaster.broadcast_update(row)
    wait_until { current.all? { |stream| received[stream].any? } }

    aggregate_failures do
      current.each { |stream| expect(received[stream]).not_to be_empty, "#{stream} received nothing" }
      legacy.each { |stream| expect(received[stream]).to be_empty, "#{stream} still receives broadcasts" }
    end
  end
end
