# frozen_string_literal: true

require "rails_helper"

# audit-fixes-0-16-0/REQ-6: capture resolved the application as
# config.application_name, then APPLICATION_NAME, then the module name. The
# backfill migration and task skipped the config, and the Rack::Attack,
# missing-translation and swallowed-exception flushers used only the config, so
# the same app's rows ended up under two Applications, or none.
RSpec.describe "RailsErrorDashboard.resolved_application_name" do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    saved_name = config.application_name
    saved_env = ENV["APPLICATION_NAME"]
    example.run
  ensure
    config.application_name = saved_name
    saved_env.nil? ? ENV.delete("APPLICATION_NAME") : ENV["APPLICATION_NAME"] = saved_env
  end

  it "prefers the config, then APPLICATION_NAME, then the app's module name" do
    config.application_name = "Shop"
    ENV["APPLICATION_NAME"] = "FromEnv"
    expect(RailsErrorDashboard.resolved_application_name).to eq("Shop")

    config.application_name = nil
    expect(RailsErrorDashboard.resolved_application_name).to eq("FromEnv")

    ENV.delete("APPLICATION_NAME")
    expect(RailsErrorDashboard.resolved_application_name).to eq(Rails.application.class.module_parent_name)
  end

  [
    RailsErrorDashboard::Commands::FlushRackAttackEvents,
    RailsErrorDashboard::Commands::FlushMissingTranslations,
    RailsErrorDashboard::Commands::FlushSwallowedExceptions
  ].each do |flusher|
    it "#{flusher.name.demodulize} files events under the application capture uses" do
      config.application_name = nil
      ENV["APPLICATION_NAME"] = "FromEnv"
      app = RailsErrorDashboard::Application.find_or_create_by_name("FromEnv")

      expect(flusher.allocate.send(:current_application_id)).to eq(app.id)
    end
  end

  # Today's schema has application_id NOT NULL, so the rows this migration
  # fills exist only in installs from before multi-app. What it decides is the
  # name of the Application it files them under, which it creates either way.
  it "backfills old errors under config.application_name" do
    config.application_name = "Shop"
    ENV.delete("APPLICATION_NAME")
    create(:error_log)

    load RailsErrorDashboard::Engine.root.join("db/migrate/20260106094256_backfill_application_for_existing_errors.rb")
    ActiveRecord::Migration.suppress_messages { BackfillApplicationForExistingErrors.new.up }

    expect(RailsErrorDashboard::Application.where(name: "Shop")).to exist
  end
end
