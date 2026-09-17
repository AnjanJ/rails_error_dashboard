# frozen_string_literal: true

require "rails_helper"

# The per-error cooldown cannot help with a bad deploy that produces 200
# DISTINCT new errors: each one is a first occurrence, and each one notifies.
# The burst cap bounds that, per process, and says once that it has engaged.
RSpec.describe "NotificationThrottler burst cap" do
  let(:throttler) { RailsErrorDashboard::Services::NotificationThrottler }
  let(:config) { RailsErrorDashboard.configuration }
  let(:now) { [ 1000.0 ] }

  before do
    throttler.clear!
    config.notification_burst_limit = 3
    config.notification_burst_window_seconds = 60
    allow(throttler).to receive(:monotonic_now) { now.first }
  end

  after do
    throttler.clear!
    RailsErrorDashboard.reset_configuration!
  end

  def decisions(count)
    Array.new(count) { throttler.burst_decision }
  end

  it "defaults to 10 notifications per 60 seconds" do
    RailsErrorDashboard.reset_configuration!

    expect(RailsErrorDashboard.configuration.notification_burst_limit).to eq(10)
    expect(RailsErrorDashboard.configuration.notification_burst_window_seconds).to eq(60)
  end

  it "notifies up to the limit, summarises once, then suppresses" do
    expect(decisions(6)).to eq(%i[notify notify notify summarize suppress suppress])
  end

  it "starts a fresh window once the window has passed" do
    decisions(5)
    now[0] += 60

    expect(decisions(5)).to eq(%i[notify notify notify summarize suppress])
  end

  it "does not reset inside the window" do
    decisions(4)
    now[0] += 59

    expect(throttler.burst_decision).to eq(:suppress)
  end

  [ 0, nil ].each do |disabled|
    it "is disabled by a limit of #{disabled.inspect}" do
      config.notification_burst_limit = disabled

      expect(decisions(50).uniq).to eq([ :notify ])
    end
  end

  it "treats a missing window as disabled rather than dividing time by nothing" do
    config.notification_burst_window_seconds = nil

    expect(decisions(50).uniq).to eq([ :notify ])
  end

  it "fails open" do
    allow(throttler).to receive(:monotonic_now).and_raise(RuntimeError, "clock broke")

    expect(throttler.burst_decision).to eq(:notify)
  end

  it "grants exactly the limit and exactly one summary under contention" do
    config.notification_burst_limit = 10
    results = Array.new(8) { Thread.new { Array.new(25) { throttler.burst_decision } } }.flat_map(&:value)

    expect(results.count(:notify)).to eq(10)
    expect(results.count(:summarize)).to eq(1)
    expect(results.count(:suppress)).to eq(189)
  end

  it "is reset by clear!" do
    decisions(5)
    throttler.clear!

    expect(throttler.burst_decision).to eq(:notify)
  end

  describe "configuration validation" do
    it "accepts zero (disabled) and positive integers" do
      config.notification_burst_limit = 0
      config.notification_burst_window_seconds = 1

      expect { config.validate! }.not_to raise_error
    end

    {
      notification_burst_limit: [ -1, "ten", 1.5 ],
      notification_burst_window_seconds: [ -1, "sixty", 0.5 ]
    }.each do |option, bad_values|
      bad_values.each do |bad|
        it "rejects #{option} = #{bad.inspect}" do
          config.public_send("#{option}=", bad)

          expect { config.validate! }.to raise_error(RailsErrorDashboard::ConfigurationError, /#{option}/)
        end
      end
    end
  end
end
