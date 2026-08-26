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

      expect(described_class).to receive(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_environment: true))
        .and_return("<tr></tr>")
      described_class.broadcast_new(row)
    end

    it "hides the environment cell with a single environment" do
      row = create(:error_log, environment: "production")

      expect(described_class).to receive(:render_partial)
        .with("rails_error_dashboard/errors/error_row", hash_including(show_environment: false))
        .and_return("<tr></tr>")
      described_class.broadcast_new(row)
    end
  end
end
