# frozen_string_literal: true

require "rails_helper"

# Counted-only storm events live in THIS process's memory until something
# writes them out. That something used to be a later admit! reaching the flush
# interval -- which makes the drain conditional on the flood continuing. When
# the errors stop (exactly when an operator starts looking), the tail of the
# burst stayed buffered indefinitely, and a deploy dropped it.
#
# The engine now wires two drains, mirroring the Rack::Attack precedent:
#
#   Rails.application.executor.to_complete { Gate.flush_if_due! }
#   at_exit                                { Gate.drain! }
#
# The wiring itself is guarded on enable_storm_protection at boot, and the
# dummy app disables storm protection, so these examples exercise the two
# entry points the engine calls rather than the registration.
RSpec.describe "storm count drain" do
  let(:gate) { RailsErrorDashboard::Services::StormProtection::Gate }
  let(:logs) { RailsErrorDashboard::ErrorLog }

  def boom(message = "drain boom")
    StandardError.new(message).tap do |error|
      error.set_backtrace([ "#{Rails.root}/app/models/audit.rb:12:in 'run'" ])
    end
  end

  before do
    RailsErrorDashboard.reset_configuration!
    config = RailsErrorDashboard.configuration
    config.enable_storm_protection = true
    config.storm_notification = false
    config.async_logging = false
    gate.reset!
    allow(gate.breaker).to receive(:record!).and_return(:open)
    allow(gate.breaker).to receive(:episode_snapshot).and_return(nil)
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(false)
  end

  after do
    gate.reset!
    RailsErrorDashboard.reset_configuration!
  end

  describe ".flush_if_due! (end of every request and job)" do
    it "drains the buffer once the interval has elapsed" do
      # Pin the interval: another spec leaves it at 3600 and only restores it
      # in its own after-hook, so this example was order-dependent.
      RailsErrorDashboard.configuration.storm_flush_interval_seconds = 30
      allow(gate).to receive(:monotonic_now).and_return(100.0)
      3.times { gate.admit!(boom) }
      expect(gate.count_buffer.any?).to be true

      allow(gate).to receive(:monotonic_now).and_return(131.0)

      expect { gate.flush_if_due! }
        .to have_enqueued_job(RailsErrorDashboard::StormFlushJob)
      expect(gate.count_buffer.any?).to be false
    end

    # The whole point of the interval gate: a flood must not become one
    # enqueue per request.
    it "does nothing before the interval has elapsed" do
      RailsErrorDashboard.configuration.storm_flush_interval_seconds = 3600
      3.times { gate.admit!(boom) }

      expect { gate.flush_if_due! }
        .not_to have_enqueued_job(RailsErrorDashboard::StormFlushJob)
      expect(gate.count_buffer.any?).to be true
    end

    it "is a no-op when storm protection is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false

      expect { gate.flush_if_due! }.not_to raise_error
    end
  end

  describe ".drain! (process exit)" do
    # A shutdown drain that respected the interval would drop the very tail it
    # exists to save.
    it "writes everything buffered even though the interval has not elapsed" do
      RailsErrorDashboard.configuration.storm_flush_interval_seconds = 3600
      4.times { gate.admit!(boom) }

      expect { gate.drain! }.to change(logs, :count).by(1)

      expect(logs.sole.occurrence_count).to eq(4)
      expect(gate.count_buffer.any?).to be false
    end

    # At process exit a job handed to the queue may never be picked up, so the
    # drain writes through the command rather than enqueueing.
    it "writes synchronously rather than enqueueing a job" do
      4.times { gate.admit!(boom) }

      expect { gate.drain! }
        .not_to have_enqueued_job(RailsErrorDashboard::StormFlushJob)
      expect(logs.sum(:occurrence_count)).to eq(4)
    end

    it "does nothing when there is nothing buffered" do
      expect { gate.drain! }.not_to change(logs, :count)
    end

    # at_exit runs while the process is tearing down; a raise there would
    # surface as a confusing crash in whatever is exiting.
    it "never raises, even when the write fails" do
      3.times { gate.admit!(boom) }
      allow(RailsErrorDashboard::Commands::FlushStormCounts)
        .to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished, "gone")

      expect { gate.drain! }.not_to raise_error
    end

    it "is a no-op when storm protection is disabled" do
      RailsErrorDashboard.configuration.enable_storm_protection = false

      expect { gate.drain! }.not_to raise_error
    end
  end
end
