# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Commands::BackfillEnvironments do
  let!(:application) { create(:application) }

  def legacy(environment_info:, environment: nil)
    create(:error_log, application: application, environment: environment,
           environment_info: environment_info&.to_json)
  end

  it "fills environment from environment_info.rails_env where it is NULL" do
    row = legacy(environment_info: { rails_env: "production", ruby_version: "3.4.5" })
    expect(described_class.call).to eq(1)
    expect(row.reload.environment).to eq("production")
  end

  it "leaves rows without a rails_env untouched and still counts nothing for them" do
    no_info = legacy(environment_info: nil)
    no_env = legacy(environment_info: { ruby_version: "3.4.5" })
    expect(described_class.call).to eq(0)
    expect(no_info.reload.environment).to be_nil
    expect(no_env.reload.environment).to be_nil
  end

  it "never overwrites a row that already has an environment" do
    row = legacy(environment_info: { rails_env: "production" }, environment: "staging")
    described_class.call
    expect(row.reload.environment).to eq("staging")
  end

  it "survives malformed environment_info JSON" do
    row = create(:error_log, application: application, environment: nil, environment_info: "{not json")
    expect { described_class.call }.not_to raise_error
    expect(row.reload.environment).to be_nil
  end

  it "truncates to the column limit" do
    row = legacy(environment_info: { rails_env: "e" * 80 })
    described_class.call
    expect(row.reload.environment.length).to eq(64)
  end
end
