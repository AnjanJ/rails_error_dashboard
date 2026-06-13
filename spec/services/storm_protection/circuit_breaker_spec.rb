# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::StormProtection::CircuitBreaker do
  # Injected, manually-advanced clock — every transition is deterministic.
  let(:clock) do
    Class.new {
      def initialize = @now = 1000.0
      def call = @now
      def advance(seconds) = @now += seconds
    }.new
  end
  let(:breaker) { described_class.new(clock: clock) }

  after { RailsErrorDashboard.reset_configuration! }

  # Defaults: shedding at 10/s, open at 50/s (fast-trip at 500/bucket),
  # cooldown 60s, bucket 10s, two calm buckets to close.

  def fire(count)
    count.times { breaker.record! }
  end

  # Fill the current 10s bucket with `events`, then advance time and fire one
  # record to trigger the roll that evaluates it. The trigger event becomes a
  # single stray in the next bucket (0.1/s — far below any threshold).
  def run_bucket(events)
    fire(events)
    clock.advance(10)
    breaker.record!
  end

  describe "closed state" do
    it "starts closed" do
      expect(breaker.state).to eq(:closed)
    end

    it "stays closed below the shedding threshold" do
      run_bucket(50) # 5/s < 10/s
      expect(breaker.state).to eq(:closed)
    end

    it "enters shedding when a bucket exceeds the shedding threshold" do
      run_bucket(150) # 15/s
      expect(breaker.state).to eq(:shedding)
    end
  end

  describe "fast trip" do
    it "opens mid-bucket without waiting for the roll" do
      fire(500) # 50/s * 10s — trips inside the bucket
      expect(breaker.state).to eq(:open)
    end

    it "begins an episode flagged reached_open" do
      fire(500)
      episode = breaker.episode_snapshot
      expect(episode).to be_present
      expect(episode[:reached_open]).to be true
      expect(episode[:ended_at]).to be_nil
    end
  end

  describe "shedding state" do
    before { run_bucket(150) } # → :shedding

    it "escalates to open when the rate keeps climbing" do
      fire(500)
      expect(breaker.state).to eq(:open)
    end

    it "needs two consecutive calm buckets to close (hysteresis)" do
      run_bucket(10) # ~1.1/s < 5/s (half of shedding): calm bucket 1
      expect(breaker.state).to eq(:shedding)
      run_bucket(10) # calm bucket 2
      expect(breaker.state).to eq(:closed)
    end

    it "resets the calm streak when the rate bounces back" do
      run_bucket(10)  # calm 1
      run_bucket(80)  # ~8.1/s — above half-threshold, streak resets
      run_bucket(10)  # calm 1 again
      expect(breaker.state).to eq(:shedding)
      run_bucket(10)  # calm 2
      expect(breaker.state).to eq(:closed)
    end

    it "marks the episode ended when it closes" do
      run_bucket(10)
      run_bucket(10)
      expect(breaker.episode_snapshot[:ended_at]).to be_present
    end
  end

  describe "open → half_open → closed recovery" do
    before { fire(500) } # fast-trip open

    it "stays open during the cooldown even when calm" do
      run_bucket(5)
      expect(breaker.state).to eq(:open)
    end

    it "goes half_open after the cooldown when the rate is calm" do
      7.times { run_bucket(5) } # 70s elapsed > 60s cooldown, all calm
      expect(breaker.state).to eq(:half_open)
    end

    it "closes after two calm half_open buckets" do
      7.times { run_bucket(5) } # → half_open
      run_bucket(5)
      run_bucket(5)
      expect(breaker.state).to eq(:closed)
      expect(breaker.episode_snapshot[:ended_at]).to be_present
    end

    it "re-opens from half_open when the storm resumes" do
      7.times { run_bucket(5) } # → half_open
      fire(500)
      expect(breaker.state).to eq(:open)
    end
  end

  describe "episode tracking" do
    it "has no episode while closed and calm" do
      fire(10)
      expect(breaker.episode_snapshot).to be_nil
    end

    it "tracks peak rate per minute" do
      run_bucket(200) # 20/s → 1200/min at the roll
      expect(breaker.episode_snapshot[:peak_rate_per_minute]).to be >= 1200
    end

    it "clear_closed_episode! keeps active episodes and removes ended ones" do
      fire(500)
      breaker.clear_closed_episode!
      expect(breaker.episode_snapshot).to be_present # still active

      9.times { run_bucket(5) } # cooldown → half_open → closed
      expect(breaker.state).to eq(:closed)
      breaker.clear_closed_episode!
      expect(breaker.episode_snapshot).to be_nil
    end
  end

  describe "configurable thresholds" do
    it "respects a custom open threshold" do
      RailsErrorDashboard.configuration.storm_open_threshold_per_second = 2
      fire(20) # fast-trip at the lower 2/s * 10s = 20
      expect(breaker.state).to eq(:open)
    end
  end

  describe "reset!" do
    it "returns to a clean closed state" do
      fire(500)
      breaker.reset!
      expect(breaker.state).to eq(:closed)
      expect(breaker.episode_snapshot).to be_nil
    end
  end
end
