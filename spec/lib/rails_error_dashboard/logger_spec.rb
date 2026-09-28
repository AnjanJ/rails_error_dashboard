# frozen_string_literal: true

require "rails_helper"

# validate! accepted log_level :fatal, but LOG_LEVELS had no :fatal, so every
# internal log call compared an Integer with nil and raised, including the
# Logger.error calls inside rescue blocks.
RSpec.describe RailsErrorDashboard::Logger do
  let(:config) { RailsErrorDashboard.configuration }

  around do |example|
    original = [ config.log_level, config.enable_internal_logging ]
    example.run
  ensure
    config.log_level, config.enable_internal_logging = original
  end

  before do
    config.enable_internal_logging = true
    %i[debug info warn error].each { |level| allow(Rails.logger).to receive(level) }
  end

  def log_everything
    described_class.debug("debug message")
    described_class.info("info message")
    described_class.warn("warn message")
    described_class.error("error message")
  end

  it "accepts at boot exactly the levels it defines" do
    described_class::LOG_LEVELS.each_key do |level|
      config.log_level = level
      expect { config.validate! }.not_to raise_error, "validate! rejected #{level.inspect}"
    end

    config.log_level = :verbose
    expect { config.validate! }.to raise_error(RailsErrorDashboard::ConfigurationError, /log_level/)
  end

  it "defines :fatal, which validate! has always accepted" do
    expect(described_class::LOG_LEVELS).to include(:fatal)
  end

  it "logs nothing and raises nothing at :fatal" do
    config.log_level = :fatal

    expect { log_everything }.not_to raise_error
    expect(Rails.logger).not_to have_received(:error)
  end

  it "never raises, whatever log_level holds" do
    [ :nonsense, "error", 42 ].each do |level|
      config.log_level = level
      expect { log_everything }.not_to raise_error, "raised for log_level #{level.inspect}"
    end
  end

  it "still logs errors at :error" do
    config.log_level = :error

    log_everything

    expect(Rails.logger).to have_received(:error).with("[RailsErrorDashboard] error message")
    expect(Rails.logger).not_to have_received(:warn)
  end

  it "still logs debug messages at :debug with internal logging on" do
    config.log_level = :debug

    log_everything

    expect(Rails.logger).to have_received(:debug).with("[RailsErrorDashboard] debug message")
  end

  it "logs nothing at :silent" do
    config.log_level = :silent

    log_everything

    expect(Rails.logger).not_to have_received(:error)
  end
end
