# frozen_string_literal: true

require "rails_helper"

# The live-updates channel subclasses ActionCable::Channel::Base, so a host
# without Action Cable must never load it: not through the engine, and not
# through production eager loading.
RSpec.describe "Loading the live-updates channel" do
  let(:channel_file) do
    File.expand_path("../../../lib/rails_error_dashboard/live_updates_channel.rb", __dir__)
  end

  # live-updates-hardening-0-17/REQ-12
  it "loads nothing when Action Cable is not loaded" do
    hide_const("ActionCable")
    allow(RailsErrorDashboard::Engine).to receive(:require).and_call_original

    expect(RailsErrorDashboard::Engine.load_live_updates_channel).to be false
    expect(RailsErrorDashboard::Engine).not_to have_received(:require)
  end

  it "loads the channel when Action Cable is loaded" do
    expect(RailsErrorDashboard::Engine.load_live_updates_channel).to be true
    expect(defined?(RailsErrorDashboard::LiveUpdatesChannel)).to eq("constant")
  end

  # live-updates-hardening-0-17/REQ-12: eager loading never reaches the file.
  it "keeps the channel file off every autoload and eager-load path" do
    expect(File).to exist(channel_file)

    roots = ActiveSupport::Dependencies.autoload_paths +
            Rails.application.config.eager_load_paths +
            RailsErrorDashboard::Engine.config.eager_load_paths
    inside = roots.map(&:to_s).select { |root| channel_file.start_with?(File.join(root, "")) }

    expect(inside).to be_empty
  end
end
