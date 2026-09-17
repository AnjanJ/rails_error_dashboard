# frozen_string_literal: true

require "rails_helper"

# The buffer is a per-thread Hash. These examples drive the bookkeeping
# directly rather than through TracePoint, so every count is exact.
RSpec.describe "SwallowedExceptionTracker buffer bounds and flush deadline" do
  include ActiveJob::TestHelper

  let(:tracker) { RailsErrorDashboard::Services::SwallowedExceptionTracker }
  let(:config) { RailsErrorDashboard.configuration }
  let(:overflow) { tracker::RAISE_OVERFLOW_KEY }

  before do
    tracker.clear!
    config.swallowed_exception_max_cache_size = 5
    config.swallowed_exception_flush_interval = 60
  end

  after do
    tracker.clear!
    RailsErrorDashboard.reset_configuration!
  end

  def bump(hash, key, times = 1)
    times.times { tracker.send(:increment!, hash, key, overflow) }
  end

  describe "eviction" do
    # "Oldest" used to mean first INSERTED, so the busiest key in the process
    # (inserted first, hit constantly) was the first one thrown away, and its
    # count vanished with it.
    it "keeps a hot key and evicts the least recently UPDATED one into the overflow bucket" do
      counts = {}
      bump(counts, "Hot|a.rb:1", 500)
      %w[B C D E].each { |k| bump(counts, "#{k}|x.rb:1", 2) }
      bump(counts, "Hot|a.rb:1") # touched again: now the most recent

      bump(counts, "New|n.rb:1")

      expect(counts).to include("Hot|a.rb:1" => 501, "New|n.rb:1" => 1)
      # B goes first; the overflow bucket then takes a slot itself, so C follows.
      expect(counts.keys).to contain_exactly("D|x.rb:1", "E|x.rb:1", "Hot|a.rb:1", "New|n.rb:1", overflow)
      expect(counts[overflow]).to eq(4)
      expect(counts.values.sum).to eq(510)
    end

    it "conserves the total however many keys rotate through" do
      counts = {}
      200.times { |i| bump(counts, "K#{i}|f.rb:#{i}", 3) }

      expect(counts.values.sum).to eq(600)
      expect(counts.size).to be <= config.swallowed_exception_max_cache_size
    end

    it "never evicts the overflow bucket" do
      counts = {}
      50.times { |i| bump(counts, "K#{i}|f.rb:#{i}") }

      expect(counts).to have_key(overflow)
      expect(counts[overflow]).to eq(50 - (counts.size - 1))
    end

    it "terminates when only the overflow bucket is left (max size 0)" do
      config.swallowed_exception_max_cache_size = 0
      counts = {}

      expect { Timeout.timeout(2) { 20.times { |i| bump(counts, "K#{i}|f.rb:#{i}") } } }.not_to raise_error
      expect(counts.keys).to eq([ overflow ])
      expect(counts[overflow]).to eq(20)
    end

    it "uses overflow keys the flush command stores under a recognisable class" do
      expect(tracker::RAISE_OVERFLOW_KEY.split("|", 2)).to eq([ "[overflow]", "[overflow]" ])
      expect(tracker::RESCUE_OVERFLOW_KEY).to eq("[overflow]|[overflow]->[overflow]")

      RailsErrorDashboard::Commands::FlushSwallowedExceptions.call(
        raise_counts: { tracker::RAISE_OVERFLOW_KEY => 7 },
        rescue_counts: { tracker::RESCUE_OVERFLOW_KEY => 4 }
      )

      row = RailsErrorDashboard::SwallowedException.find_by!(exception_class: "[overflow]")
      expect(row.raise_count).to eq(7)
      expect(RailsErrorDashboard::SwallowedException.where(exception_class: "[overflow]").sum(:rescue_count)).to eq(4)
    end
  end

  describe "flush deadline" do
    let(:now) { [ 5000.0 ] }

    before { allow(tracker).to receive(:monotonic_now) { now.first } }

    def buffer_one_raise
      Thread.current[tracker::RAISE_THREAD_KEY] = {}
      tracker.send(:increment!, Thread.current[tracker::RAISE_THREAD_KEY], "Foo|a.rb:1", overflow)
      tracker.send(:arm_deadline!)
    end

    # The old guard was `last_flush ||= now`, first evaluated by the SECOND
    # event, and only ever evaluated by another rescue on the same thread.
    it "flush_if_due! flushes a buffer whose deadline has passed, with no further event" do
      buffer_one_raise
      now[0] += 61

      expect { tracker.flush_if_due! }.to change { tracker.current_raises.size }.from(1).to(0)
      expect(RailsErrorDashboard::SwallowedException.where(exception_class: "Foo").sum(:raise_count)).to eq(1)
    end

    it "does not flush before the interval" do
      buffer_one_raise
      now[0] += 59

      expect { tracker.flush_if_due! }.not_to(change { tracker.current_raises.size })
    end

    it "arms the deadline on the FIRST event, not the second" do
      buffer_one_raise
      now[0] += 40
      tracker.send(:arm_deadline!) # a later event must not push the deadline out
      now[0] += 21

      expect { tracker.flush_if_due! }.to change { tracker.current_raises.size }.to(0)
    end

    it "re-arms for the next batch after a flush" do
      buffer_one_raise
      now[0] += 61
      tracker.flush_if_due!

      buffer_one_raise
      now[0] += 30
      expect { tracker.flush_if_due! }.not_to(change { tracker.current_raises.size })
    end

    it "is a no-op on an empty buffer and never raises" do
      expect { tracker.flush_if_due! }.not_to raise_error

      allow(tracker).to receive(:monotonic_now).and_raise(RuntimeError, "clock broke")
      expect { tracker.flush_if_due! }.not_to raise_error
    end
  end

  it "is drained by the executor at the end of a unit of work when detection is on" do
    source = File.read(RailsErrorDashboard::Engine.root.join("lib/rails_error_dashboard/engine.rb"))

    expect(source).to match(/detect_swallowed_exceptions.*?executor\.to_complete.*?SwallowedExceptionTracker\.flush_if_due!/m)
  end
end
