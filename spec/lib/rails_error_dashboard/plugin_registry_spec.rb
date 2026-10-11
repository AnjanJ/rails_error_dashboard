# frozen_string_literal: true

require "rails_helper"

# A plugin is host code inside RED's own paths. A nameless plugin used to be
# appended before anything read its name, after which every later register,
# find and info call raised; on_register and enabled? ran with no rescue.
RSpec.describe RailsErrorDashboard::PluginRegistry do
  def plugin_class(name: "spec-plugin", &block)
    Class.new(RailsErrorDashboard::Plugin) do
      define_method(:name) { name } unless name == :unimplemented
      class_eval(&block) if block
    end
  end

  before { described_class.clear }
  after { described_class.clear }

  describe ".register" do
    it "refuses a plugin that does not implement #name, registering nothing" do
      expect {
        described_class.register(plugin_class(name: :unimplemented).new)
      }.to raise_error(ArgumentError, /must implement #name/)

      expect(described_class.plugins).to be_empty
      # The registry still works afterwards.
      expect(described_class.register(plugin_class.new)).to be(true)
      expect(described_class.names).to eq([ "spec-plugin" ])
    end

    it "refuses a blank name" do
      expect { described_class.register(plugin_class(name: "  ").new) }.to raise_error(ArgumentError)
      expect(described_class.plugins).to be_empty
    end

    it "does not register a plugin whose on_register raises, and logs it" do
      allow(RailsErrorDashboard::Logger).to receive(:error)
      klass = plugin_class { def on_register = raise("boot failed") }

      expect(described_class.register(klass.new)).to be(false)

      expect(described_class.plugins).to be_empty
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/spec-plugin.*on_register.*boot failed/)
    end

    it "skips a duplicate name" do
      described_class.register(plugin_class.new)
      expect(described_class.register(plugin_class.new)).to be(false)
      expect(described_class.count).to eq(1)
    end
  end

  describe ".dispatch" do
    it "treats a raising enabled? as disabled and still runs the other plugins" do
      allow(RailsErrorDashboard::Logger).to receive(:error)
      seen = []
      broken = plugin_class(name: "broken") { def enabled? = raise("config missing") }
      fine = plugin_class(name: "fine")
      fine.define_method(:on_error_logged) { |e| seen << e }
      described_class.register(broken.new)
      described_class.register(fine.new)

      expect { described_class.dispatch(:on_error_logged, :payload) }.not_to raise_error

      expect(seen).to eq([ :payload ])
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/broken.*enabled\?.*config missing/)
    end

    it "logs a failing hook without depending on name or version answering" do
      allow(RailsErrorDashboard::Logger).to receive(:error)
      klass = plugin_class(name: "flaky") do
        def on_error_logged(_e) = raise("hook down")
        def version = raise("no version")
      end
      described_class.register(klass.new)

      expect { described_class.dispatch(:on_error_logged, :payload) }.not_to raise_error
      expect(RailsErrorDashboard::Logger).to have_received(:error).with(/flaky.*on_error_logged.*hook down/)
      expect(RailsErrorDashboard::Logger).to have_received(:error).with("Plugin version: unknown")
    end
  end

  describe ".info" do
    it "describes a plugin whose enabled? raises as disabled rather than raising" do
      allow(RailsErrorDashboard::Logger).to receive(:error)
      described_class.register(plugin_class(name: "broken") { def enabled? = raise("x") }.new)

      expect(described_class.info).to eq([ { name: "broken", version: "1.0.0", description: "No description provided", enabled: false } ])
    end
  end
end
