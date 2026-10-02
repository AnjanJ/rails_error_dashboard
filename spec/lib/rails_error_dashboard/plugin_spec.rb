# frozen_string_literal: true

require "rails_helper"

# Every event the gem dispatches must exist on the base Plugin as a no-op, so a
# plugin that overrides only the hooks it cares about never fails on the rest.
# The list is read from the source, so a hook added later is covered too.
RSpec.describe RailsErrorDashboard::Plugin do
  dispatched = Dir[File.join(RailsErrorDashboard::Engine.root, "{lib,app}/**/*.rb")]
    .flat_map { |file| File.read(file).scan(/PluginRegistry\.dispatch\(:(\w+)/).flatten }
    .uniq.sort

  let(:plugin_class) do
    Class.new(described_class) do
      def name = "spec-plugin"
    end
  end
  let(:plugin) { plugin_class.new }

  it "finds the dispatched events in the source" do
    expect(dispatched).to include("on_error_logged", "on_error_muted", "on_error_reopened")
  end

  dispatched.each do |event|
    it "defines #{event} as a no-op" do
      expect(described_class.instance_method(event).owner).to eq(described_class)
      expect(plugin.public_send(event, :payload)).to be_nil
    end
  end

  it "logs no failure when every dispatched event reaches a plugin that overrides none of them" do
    RailsErrorDashboard::PluginRegistry.register(plugin)
    allow(RailsErrorDashboard::Logger).to receive(:error)

    dispatched.each { |event| RailsErrorDashboard::PluginRegistry.dispatch(event.to_sym, :payload) }

    expect(RailsErrorDashboard::Logger).not_to have_received(:error)
  ensure
    RailsErrorDashboard::PluginRegistry.unregister("spec-plugin")
  end
end
