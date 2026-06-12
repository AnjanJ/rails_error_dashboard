# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::StormProtection::FingerprintBuckets do
  let(:clock) do
    Class.new {
      def initialize = @now = 1000.0
      def call = @now
      def advance(seconds) = @now += seconds
    }.new
  end
  let(:buckets) { described_class.new(clock: clock) }

  after { RailsErrorDashboard.reset_configuration! }

  # Defaults: 30 full/min per fingerprint, keep every 10th past the cap,
  # calm context sampling after 25 full-context/day keeping every 10th,
  # 1000 max tracked fingerprints.

  describe "per-minute fidelity ladder" do
    before do
      # Isolate minute-window logic from daily context sampling
      RailsErrorDashboard.configuration.context_sampling_threshold_per_day = 100_000
    end

    it "grants :full under the per-minute cap" do
      decisions = Array.new(25) { buckets.decide("abc") }
      expect(decisions).to all(eq(:full))
    end

    it "drops to :lite immediately past the cap (fresh exemplar guarantee)" do
      30.times { buckets.decide("abc") }
      expect(buckets.decide("abc")).to eq(:lite) # event 31
    end

    it "keeps every Nth as :lite and counts the rest" do
      31.times { buckets.decide("abc") } # through the cap + first :lite
      next_nine = Array.new(9) { buckets.decide("abc") } # events 32..40
      expect(next_nine.last).to eq(:lite)             # event 40: (40-30) % 10 == 0
      expect(next_nine[0..7]).to all(eq(:count_only)) # events 32..39
    end

    it "resets the window after 60 seconds" do
      40.times { buckets.decide("abc") }
      expect(buckets.decide("abc")).to eq(:count_only)

      clock.advance(61)
      expect(buckets.decide("abc")).to eq(:full)
    end

    it "tracks fingerprints independently" do
      40.times { buckets.decide("abc") }
      expect(buckets.decide("abc")).to eq(:count_only)
      expect(buckets.decide("xyz")).to eq(:full)
    end
  end

  describe "calm-mode context sampling (daily)" do
    before do
      RailsErrorDashboard.configuration.context_sampling_threshold_per_day = 5
      RailsErrorDashboard.configuration.context_sampling_keep_every = 3
      RailsErrorDashboard.configuration.storm_fingerprint_full_per_minute = 1000 # isolate daily logic
    end

    it "grants :full up to the daily threshold, then samples context" do
      first_five = Array.new(5) { buckets.decide("abc") }
      expect(first_five).to all(eq(:full))

      # Events 6..9: full only when day-count % 3 == 0 (6 and 9)
      expect(buckets.decide("abc")).to eq(:full)  # 6
      expect(buckets.decide("abc")).to eq(:lite)  # 7
      expect(buckets.decide("abc")).to eq(:lite)  # 8
      expect(buckets.decide("abc")).to eq(:full)  # 9
    end

    it "resets the daily counter after 24 hours" do
      9.times { buckets.decide("abc") }
      expect(buckets.decide("abc")).to eq(:lite) # 10

      clock.advance(86_401)
      expect(buckets.decide("abc")).to eq(:full)
    end
  end

  describe "bounded memory" do
    before { RailsErrorDashboard.configuration.storm_max_tracked_fingerprints = 3 }

    it "stops tracking new fingerprints at the cap and decides :full" do
      buckets.decide("a")
      buckets.decide("b")
      buckets.decide("c")
      # Map full: unseen keys untracked — calm weather makes :full harmless;
      # a unique-fingerprint storm is the global breaker's job.
      expect(buckets.decide("d")).to eq(:full)
      expect(buckets.decide("e")).to eq(:full)
    end

    it "keeps limiting already-tracked fingerprints when full" do
      buckets.decide("a")
      buckets.decide("b")
      buckets.decide("c")
      39.times { buckets.decide("a") }
      expect(buckets.decide("a")).to eq(:count_only)
    end
  end

  describe "reset!" do
    it "clears all tracked state" do
      40.times { buckets.decide("abc") }
      buckets.reset!
      expect(buckets.decide("abc")).to eq(:full)
    end
  end
end
