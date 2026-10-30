# frozen_string_literal: true

require "rails_helper"

# Decision 0004: neither option ever did anything, so both warn and store nothing
# from 0.18, and an initializer that still assigns them keeps booting.
RSpec.describe "Deprecated configuration options" do
  let(:config) { RailsErrorDashboard::Configuration.new }

  before { allow(Rails.logger).to receive(:warn) }
  after { RailsErrorDashboard::Deprecation.reset! }

  { async_adapter: "4", llm_observability_content_capture: "6" }.each do |option, req|
    describe option.to_s do
      it "logs one deprecation, however often it's assigned (deprecations-0-18/REQ-#{req})" do
        3.times { config.public_send("#{option}=", :anything) }

        expect(Rails.logger).to have_received(:warn).with(/DEPRECATION: config\.#{option} /).once
      end

      it "says to delete the line, and when it goes (deprecations-0-18/REQ-1)" do
        config.public_send("#{option}=", :anything)

        expect(Rails.logger).to have_received(:warn).with(/Delete the line.*2\.0/)
      end

      it "ignores the value, so the reader returns nil (deprecations-0-18/REQ-#{req})" do
        config.public_send("#{option}=", :anything)

        expect(config.public_send(option)).to be_nil
      end

      it "reads nil without warning, for an app that only reads it (deprecations-0-18/REQ-#{req})" do
        expect(config.public_send(option)).to be_nil
        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end

  it "accepts any async_adapter in validate!, which it used to reject (deprecations-0-18/REQ-5)" do
    config.async_logging = true
    config.async_adapter = :resque

    expect { config.validate! }.not_to raise_error
  end

  describe "the Settings page", type: :request do
    let(:live) { RailsErrorDashboard.configuration }

    around do |example|
      saved = [ live.authenticate_with, live.async_logging ]
      live.authenticate_with = -> { true }
      example.run
    ensure
      live.authenticate_with, live.async_logging = saved
    end

    # Set here, not in the around: the suite resets configuration between them,
    # and with async logging off the row would be hidden anyway.
    it "shows neither option, with async logging on (deprecations-0-18/REQ-9)" do
      live.async_logging = true

      get "/error_dashboard/settings"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("async_logging")
      expect(response.body).not_to match(/async_adapter|Job queue adapter|llm_observability_content_capture/)
    end
  end
end
