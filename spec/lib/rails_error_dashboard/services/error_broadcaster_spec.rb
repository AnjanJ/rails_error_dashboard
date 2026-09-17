# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ErrorBroadcaster do
  let(:error_log) { create(:error_log) }

  describe ".available?" do
    it "returns false when Turbo is not defined" do
      hide_const("Turbo")
      expect(described_class.available?).to be false
    end

    it "returns false when ActionCable is not defined" do
      hide_const("ActionCable")
      expect(described_class.available?).to be false
    end

    it "returns true when Turbo and ActionCable are available" do
      stub_const("Turbo", Module.new)
      pubsub = double("pubsub")
      server = double("server", pubsub: pubsub)
      cable = Module.new
      cable.define_singleton_method(:server) { server }
      stub_const("ActionCable", cable)

      # Clear any circuit breaker state from other tests
      described_class.instance_variable_set(:@broadcast_unavailable_until, nil)

      expect(described_class.available?).to be true
    end

    it "returns false and activates circuit breaker when pubsub adapter gem is missing (Gem::LoadError)" do
      stub_const("Turbo", Module.new)
      server = double("server")
      allow(server).to receive(:respond_to?).with(:pubsub).and_return(true)
      allow(server).to receive(:pubsub).and_raise(Gem::LoadError, "redis is not part of the bundle. Add it to your Gemfile.")
      cable = Module.new
      cable.define_singleton_method(:server) { server }
      stub_const("ActionCable", cable)

      described_class.instance_variable_set(:@broadcast_unavailable_until, nil)

      expect(described_class.available?).to be false
      expect(described_class.instance_variable_get(:@broadcast_unavailable_until)).to be_a(ActiveSupport::TimeWithZone).or be_a(Time)
    end
  end

  # Helper to stub ActionCable with a working server/pubsub for available? check
  def stub_actioncable_available
    pubsub = double("pubsub")
    server = double("server", pubsub: pubsub)
    cable = Module.new
    cable.define_singleton_method(:server) { server }
    stub_const("ActionCable", cable)
    described_class.instance_variable_set(:@broadcast_unavailable_until, nil)
  end

  describe ".broadcast_new" do
    it "handles nil error_log safely" do
      expect { described_class.broadcast_new(nil) }.not_to raise_error
    end

    context "when broadcasting is not available" do
      before { hide_const("Turbo") }

      it "returns nil without error" do
        expect { described_class.broadcast_new(error_log) }.not_to raise_error
      end
    end

    context "when broadcasting raises an error" do
      it "rescues the error and does not re-raise" do
        stub_const("Turbo", Module.new)
        stub_actioncable_available
        turbo_channel = class_double("Turbo::StreamsChannel").as_stubbed_const
        allow(turbo_channel).to receive(:broadcast_prepend_to).and_raise(StandardError, "broadcast failed")
        allow(turbo_channel).to receive(:broadcast_replace_to)

        expect { described_class.broadcast_new(error_log) }.not_to raise_error
      end
    end
  end

  describe ".broadcast_update" do
    it "handles nil error_log safely" do
      expect { described_class.broadcast_update(nil) }.not_to raise_error
    end

    context "when broadcasting is not available" do
      before { hide_const("Turbo") }

      it "returns nil without error" do
        expect { described_class.broadcast_update(error_log) }.not_to raise_error
      end
    end

    context "when broadcasting raises an error" do
      it "rescues the error and does not re-raise" do
        stub_const("Turbo", Module.new)
        stub_actioncable_available
        turbo_channel = class_double("Turbo::StreamsChannel").as_stubbed_const
        allow(turbo_channel).to receive(:broadcast_prepend_to)
        allow(turbo_channel).to receive(:broadcast_replace_to).and_raise(StandardError, "broadcast failed")

        expect { described_class.broadcast_update(error_log) }.not_to raise_error
      end
    end
  end

  describe ".broadcast_stats" do
    context "when broadcasting is not available" do
      before { hide_const("Turbo") }

      it "returns nil without error" do
        expect { described_class.broadcast_stats }.not_to raise_error
      end
    end
  end

  describe ".broadcast_new environment column" do
    before do
      allow(described_class).to receive(:available?).and_return(true)
      allow(described_class).to receive(:broadcast_stats)
      stub_const("Turbo::StreamsChannel", double("StreamsChannel", broadcast_prepend_to: true))
    end

    it "shows the environment cell only when more than one environment exists" do
      create(:error_log, environment: "staging")
      row = create(:error_log, environment: "production")
      allow(described_class).to receive(:render_partial).and_return("<tr></tr>")
      # Column visibility is cached for a minute (creating the rows above
      # already broadcast, and cached "one environment").
      Rails.cache.clear

      described_class.broadcast_new(row)

      # The global table. The row's own application has one environment, so its
      # per-application rendering hides the cell -- the rule the index applies.
      expect(described_class).to have_received(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_environment: true)).once
      expect(described_class).to have_received(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_environment: false)).once
    end

    it "hides the environment cell with a single environment" do
      row = create(:error_log, environment: "production")
      allow(described_class).to receive(:render_partial).and_return("<tr></tr>")

      described_class.broadcast_new(row)

      expect(described_class).to have_received(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_environment: false)).twice
      expect(described_class).not_to have_received(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_environment: true))
    end
  end
  # A capture broadcasts from inside the host app's request thread. The stats
  # payload is the expensive half, so it is rate-limited per process, and
  # nothing at all is broadcast while storm protection is shedding load.
  describe "stats broadcast throttling" do
    let(:channel) { double("StreamsChannel", broadcast_prepend_to: true, broadcast_replace_to: true) }
    let(:stats) { { total_today: 1 } }
    let(:now) { [ 1_000.0 ] }

    before do
      described_class.reset_throttle!
      allow(described_class).to receive(:available?).and_return(true)
      allow(described_class).to receive(:render_partial).and_return("<div></div>")
      allow(described_class).to receive(:monotonic_now) { now.first }
      allow(RailsErrorDashboard::Queries::DashboardStats).to receive(:call).and_return(stats)
      allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:state).and_return(:closed)
      stub_const("Turbo::StreamsChannel", channel)
    end

    after { described_class.reset_throttle! }

    def global_stats_calls
      RailsErrorDashboard::Queries::DashboardStats
    end

    it "computes stats once for ten updates inside one second" do
      10.times do
        described_class.broadcast_update(error_log)
        now[0] += 0.1
      end

      expect(global_stats_calls).to have_received(:call).with(no_args).once
    end

    it "still broadcasts every row update while stats are throttled" do
      10.times { described_class.broadcast_update(error_log) }

      expect(channel).to have_received(:broadcast_replace_to)
        .with(anything, hash_including(target: "error_#{error_log.id}")).at_least(10).times
    end

    it "computes stats again once the interval has passed" do
      described_class.broadcast_update(error_log)
      now[0] += described_class::STATS_BROADCAST_INTERVAL + 0.01
      described_class.broadcast_update(error_log)

      expect(global_stats_calls).to have_received(:call).with(no_args).twice
    end

    it "does not let a failed stats computation consume the window forever" do
      allow(RailsErrorDashboard::Queries::DashboardStats).to receive(:call).and_raise(RuntimeError, "db down")

      expect { described_class.broadcast_update(error_log) }.not_to raise_error
    end

    %i[open half_open].each do |state|
      it "broadcasts neither rows nor stats while the storm breaker is #{state}" do
        allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:state).and_return(state)

        described_class.broadcast_new(error_log)
        described_class.broadcast_update(error_log)

        expect(channel).not_to have_received(:broadcast_prepend_to)
        expect(channel).not_to have_received(:broadcast_replace_to)
        expect(global_stats_calls).not_to have_received(:call)
      end
    end

    it "is safe under concurrent callers: one stats computation per window" do
      threads = Array.new(8) { Thread.new { 5.times { described_class.broadcast_stats } } }
      threads.each(&:join)

      expect(global_stats_calls).to have_received(:call).with(no_args).once
    end
  end
  # One global stream made every open dashboard receive every application's
  # rows and an all-applications stats payload, whatever the page was filtered to.
  describe "per-application streams" do
    # Created eagerly, BEFORE the stubs below: creating a row broadcasts by itself
    # (after_create_commit), which would count against every expectation here.
    let!(:application) { create(:application) }
    let!(:row) { create(:error_log, application: application) }
    let(:channel) { double("StreamsChannel", broadcast_prepend_to: true, broadcast_replace_to: true) }
    let(:app_id) { application.id }

    before do
      described_class.reset_throttle!
      allow(described_class).to receive(:available?).and_return(true)
      allow(described_class).to receive(:render_partial).and_return("<tr></tr>")
      allow(RailsErrorDashboard::Queries::DashboardStats).to receive(:call).and_return({ total_today: 1 })
      stub_const("Turbo::StreamsChannel", channel)
    end

    it "names streams in one place, for the view and the broadcaster alike" do
      expect(described_class.stream_name(:list)).to eq("error_list")
      expect(described_class.stream_name(:list, 7)).to eq("error_list_app_7")
      expect(described_class.stream_name(:updates, "7")).to eq("error_updates_app_7")
      expect(described_class.stream_name(:stats, nil)).to eq("error_stats")
      expect(described_class.stream_name(:stats, "")).to eq("error_stats")
    end

    it "never builds a stream name out of unvalidated text" do
      expect(described_class.stream_name(:list, "7; DROP")).to eq("error_list_app_0")
      expect { described_class.stream_name(:nope) }.to raise_error(KeyError)
    end

    it "prepends a new row to the global list and to its application's list" do
      described_class.broadcast_new(row)

      expect(channel).to have_received(:broadcast_prepend_to).with("error_list", hash_including(target: "error_list"))
      expect(channel).to have_received(:broadcast_prepend_to)
        .with("error_list_app_#{app_id}", hash_including(target: "error_list"))
    end

    it "replaces an updated row on the global and the application update streams" do
      described_class.broadcast_update(row)

      %W[error_updates error_updates_app_#{app_id}].each do |stream|
        expect(channel).to have_received(:broadcast_replace_to).with(stream, hash_including(target: "error_#{row.id}"))
      end
      expect(channel).not_to have_received(:broadcast_prepend_to)
    end

    it "renders the application cell for the global list only" do
      create(:application) # more than one application => the global table has the column
      described_class.broadcast_new(row)

      expect(described_class).to have_received(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_application: true))
      expect(described_class).to have_received(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_application: false))
    end

    it "sends all-application stats to the global stream and scoped stats to the application stream" do
      described_class.broadcast_update(row)
      described_class.broadcast_update(row)

      expect(RailsErrorDashboard::Queries::DashboardStats).to have_received(:call).with(no_args).once
      expect(RailsErrorDashboard::Queries::DashboardStats).to have_received(:call).with(application_id: app_id).once
      expect(channel).to have_received(:broadcast_replace_to).with("error_stats", hash_including(target: "dashboard_stats"))
      expect(channel).to have_received(:broadcast_replace_to)
        .with("error_stats_app_#{app_id}", hash_including(target: "dashboard_stats"))
    end

    # The capture budget: one event pays for at most one stats computation.
    it "computes at most one stats payload per event" do
      described_class.broadcast_update(row)

      expect(RailsErrorDashboard::Queries::DashboardStats).to have_received(:call).once
    end

    it "does not starve the application stream when events are rare" do
      now = [ 1_000.0 ]
      allow(described_class).to receive(:monotonic_now) { now.first }

      4.times do
        described_class.broadcast_update(row)
        now[0] += 60
      end

      expect(RailsErrorDashboard::Queries::DashboardStats).to have_received(:call).with(no_args).twice
      expect(RailsErrorDashboard::Queries::DashboardStats).to have_received(:call).with(application_id: app_id).twice
    end

    it "runs no DISTINCT scan per broadcast once column visibility is cached" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      described_class.broadcast_update(row)

      statements = []
      counter = ->(*, payload) { statements << payload[:sql] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        3.times { described_class.broadcast_update(row) }
      end

      expect(statements.grep(/SELECT DISTINCT/i)).to be_empty
    end

    it "keeps the throttle map bounded by evicting the stalest stream" do
      (described_class::MAX_THROTTLED_STREAMS + 50).times { |i| described_class.broadcast_stats(i + 1) }

      expect(described_class.throttled_stream_count).to be <= described_class::MAX_THROTTLED_STREAMS
    end
  end
end
