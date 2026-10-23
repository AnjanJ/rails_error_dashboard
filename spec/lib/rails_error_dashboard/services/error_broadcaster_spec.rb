# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::ErrorBroadcaster do
  let(:error_log) { create(:error_log) }

  # live-updates-client/REQ-2: off by default, and while off nothing is sent
  # even though a pubsub is reachable, so the switch is the only explanation.
  describe "while enable_live_updates is false" do
    before do
      skip "turbo-rails is not loaded" unless defined?(Turbo::StreamsChannel)

      @original_cable = ActionCable.server.config.cable
      ActionCable.server.config.cable = { "adapter" => "async" }
      ActionCable.server.instance_variable_set(:@pubsub, nil)
      described_class.instance_variable_set(:@broadcast_unavailable_until, nil)
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    after do
      RailsErrorDashboard.configuration.enable_live_updates = false
      ActionCable.server.config.cable = @original_cable
      ActionCable.server.instance_variable_set(:@pubsub, nil)
    end

    it "broadcasts with the switch on (control: the pubsub is reachable)" do
      RailsErrorDashboard.configuration.enable_live_updates = true

      described_class.broadcast_new(error_log)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).at_least(:once)
    end

    it "is unavailable and sends nothing from any broadcast with the switch off" do
      RailsErrorDashboard.configuration.enable_live_updates = false

      expect(described_class.available?).to be false
      described_class.broadcast_new(error_log)
      described_class.broadcast_update(error_log)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end
  end

  describe ".available?" do
    # These describe the infrastructure checks, which only run once the
    # switch is on.
    before { RailsErrorDashboard.configuration.enable_live_updates = true }
    after { RailsErrorDashboard.configuration.enable_live_updates = false }

    it "returns false when Turbo is not defined" do
      hide_const("Turbo")
      expect(described_class.available?).to be false
    end

    it "returns false when ActionCable is not defined" do
      hide_const("ActionCable")
      expect(described_class.available?).to be false
    end

    # live-updates-hardening-0-17/REQ-12: nobody could subscribe, so nothing is
    # rendered or broadcast.
    it "returns false when the live-updates channel is not loaded" do
      stub_const("Turbo", Module.new)
      server = double("server", pubsub: double("pubsub"))
      cable = Module.new
      cable.define_singleton_method(:server) { server }
      stub_const("ActionCable", cable)
      described_class.instance_variable_set(:@broadcast_unavailable_until, nil)
      expect(described_class.available?).to be true # control: everything else is available

      hide_const("RailsErrorDashboard::LiveUpdatesChannel")

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

  describe ".broadcast_new environment column" do
    before do
      allow(described_class).to receive(:available?).and_return(true)
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
  # A capture broadcasts from inside the host app's request thread, so a
  # broadcast does only the work that changes what a page shows: the rows. No
  # built-in page has a stats target. Nothing at all is broadcast while storm
  # protection is shedding load.
  describe "what a broadcast costs" do
    let(:channel) { double("StreamsChannel", broadcast_prepend_to: true, broadcast_replace_to: true) }

    before do
      allow(described_class).to receive(:available?).and_return(true)
      allow(described_class).to receive(:render_partial).and_return("<tr></tr>")
      allow(RailsErrorDashboard::Queries::DashboardStats).to receive(:call).and_return({ total_today: 1 })
      allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:state).and_return(:closed)
      stub_const("Turbo::StreamsChannel", channel)
    end

    # live-updates-hardening-0-17/REQ-10
    it "computes and broadcasts no dashboard stats for a new or a changed row" do
      described_class.broadcast_new(error_log)
      described_class.broadcast_update(error_log)

      expect(RailsErrorDashboard::Queries::DashboardStats).not_to have_received(:call)
      expect(described_class).not_to have_received(:render_partial).with("rails_error_dashboard/errors/stats", anything)
      expect(channel).not_to have_received(:broadcast_replace_to).with(anything, hash_including(target: "dashboard_stats"))
    end

    it "broadcasts every row update" do
      10.times { described_class.broadcast_update(error_log) }

      expect(channel).to have_received(:broadcast_replace_to)
        .with(anything, hash_including(target: "error_#{error_log.id}")).at_least(10).times
    end

    %i[open half_open].each do |state|
      it "broadcasts no rows while the storm breaker is #{state}" do
        allow(RailsErrorDashboard::Services::StormProtection::Gate).to receive(:state).and_return(state)

        described_class.broadcast_new(error_log)
        described_class.broadcast_update(error_log)

        expect(channel).not_to have_received(:broadcast_prepend_to)
        expect(channel).not_to have_received(:broadcast_replace_to)
      end
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
      allow(described_class).to receive(:available?).and_return(true)
      allow(described_class).to receive(:render_partial).and_return("<tr></tr>")
      stub_const("Turbo::StreamsChannel", channel)
    end

    it "names streams in one place, for the view and the broadcaster alike" do
      expect(described_class.stream_name(:list)).to eq("rails_error_dashboard:error_list")
      expect(described_class.stream_name(:list, 7)).to eq("rails_error_dashboard:error_list_app_7")
      expect(described_class.stream_name(:updates, "7")).to eq("rails_error_dashboard:error_updates_app_7")
      expect(described_class.stream_name(:updates, nil)).to eq("rails_error_dashboard:error_updates")
      expect(described_class.stream_name(:updates, "")).to eq("rails_error_dashboard:error_updates")
    end

    it "never builds a stream name out of unvalidated text" do
      expect(described_class.stream_name(:list, "7; DROP")).to eq("rails_error_dashboard:error_list_app_0")
      expect { described_class.stream_name(:nope) }.to raise_error(KeyError)
    end

    it "prepends a new row to the global list and to its application's list" do
      described_class.broadcast_new(row)

      expect(channel).to have_received(:broadcast_prepend_to).with("rails_error_dashboard:error_list", hash_including(target: "error_list"))
      expect(channel).to have_received(:broadcast_prepend_to)
        .with("rails_error_dashboard:error_list_app_#{app_id}", hash_including(target: "error_list"))
    end

    it "replaces an updated row on the global and the application update streams" do
      described_class.broadcast_update(row)

      %W[rails_error_dashboard:error_updates rails_error_dashboard:error_updates_app_#{app_id}].each do |stream|
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
  end
end
