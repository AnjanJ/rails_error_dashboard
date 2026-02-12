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
      stub_const("ActionCable", Module.new)

      expect(described_class.available?).to be true
    end
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
        stub_const("ActionCable", Module.new)
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
        stub_const("ActionCable", Module.new)
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
end
