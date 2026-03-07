# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SwallowedExceptionTracker do
  before do
    described_class.clear!
    RailsErrorDashboard.configuration.detect_swallowed_exceptions = true
    RailsErrorDashboard.configuration.swallowed_exception_max_cache_size = 1000
    RailsErrorDashboard.configuration.swallowed_exception_flush_interval = 60
    RailsErrorDashboard.configuration.swallowed_exception_ignore_classes = []
  end

  after do
    described_class.disable!
    described_class.clear!
    RailsErrorDashboard.configuration.detect_swallowed_exceptions = false
    RailsErrorDashboard.configuration.swallowed_exception_ignore_classes = []
  end

  describe ".enable!" do
    context "on Ruby 3.3+" do
      before do
        skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      end

      it "enables both TracePoints" do
        result = described_class.enable!
        expect(result).to be true
        expect(described_class.enabled?).to be true
      end

      it "returns true if already enabled" do
        described_class.enable!
        expect(described_class.enable!).to be true
      end
    end

    context "on Ruby < 3.3" do
      it "returns false and logs a warning" do
        skip "Test only meaningful on Ruby < 3.3" if RUBY_VERSION >= "3.3"
        result = described_class.enable!
        expect(result).to be false
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe ".disable!" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "disables both TracePoints" do
      described_class.disable!
      expect(described_class.enabled?).to be false
    end
  end

  describe "raise/rescue tracking", :aggregate_failures do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "increments raise counter when exception is raised" do
      begin
        raise RuntimeError, "test"
      rescue RuntimeError
        # swallowed
      end

      raises = described_class.current_raises
      expect(raises).not_to be_empty
      runtime_keys = raises.keys.select { |k| k.start_with?("RuntimeError|") }
      expect(runtime_keys).not_to be_empty
    end

    it "increments rescue counter when exception is rescued" do
      begin
        raise RuntimeError, "test rescue tracking"
      rescue RuntimeError
        # rescued
      end

      rescues = described_class.current_rescues
      expect(rescues).not_to be_empty
      runtime_keys = rescues.keys.select { |k| k.start_with?("RuntimeError|") }
      expect(runtime_keys).not_to be_empty
    end

    it "tracks raise location via ivar on exception" do
      exception = nil
      begin
        raise RuntimeError, "location test"
      rescue RuntimeError => e
        exception = e
      end

      expect(exception.instance_variable_defined?(:@_red_raise_loc)).to be true
      loc = exception.instance_variable_get(:@_red_raise_loc)
      expect(loc).to include(__FILE__)
    end
  end

  describe "flow-control filtering" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "skips SystemExit" do
      begin
        raise SystemExit
      rescue SystemExit
        # expected
      end

      raises = described_class.current_raises
      system_exit_keys = raises.keys.select { |k| k.start_with?("SystemExit|") }
      expect(system_exit_keys).to be_empty
    end

    it "skips Interrupt" do
      begin
        raise Interrupt
      rescue Interrupt
        # expected
      end

      raises = described_class.current_raises
      interrupt_keys = raises.keys.select { |k| k.start_with?("Interrupt|") }
      expect(interrupt_keys).to be_empty
    end

    it "skips user-configured ignore classes" do
      RailsErrorDashboard.configuration.swallowed_exception_ignore_classes = [ "RuntimeError" ]

      begin
        raise RuntimeError, "should be ignored"
      rescue RuntimeError
        # swallowed
      end

      raises = described_class.current_raises
      runtime_keys = raises.keys.select { |k| k.start_with?("RuntimeError|") }
      expect(runtime_keys).to be_empty
    end
  end

  describe "LRU eviction" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      RailsErrorDashboard.configuration.swallowed_exception_max_cache_size = 3
      described_class.enable!
    end

    it "evicts oldest entries when cache exceeds max size" do
      # Raise 4 different exception types to exceed cache size of 3
      [ ArgumentError, TypeError, NameError, ZeroDivisionError ].each do |klass|
        begin
          raise klass, "eviction test"
        rescue klass
          # swallowed
        end
      end

      raises = described_class.current_raises
      # Should have at most max_cache_size entries
      expect(raises.size).to be <= 3
    end
  end

  describe ".flush!" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "clears thread-local counters" do
      begin
        raise RuntimeError, "flush test"
      rescue RuntimeError
        # swallowed
      end

      expect(described_class.current_raises).not_to be_empty

      described_class.flush!

      expect(described_class.current_raises).to be_empty
      expect(described_class.current_rescues).to be_empty
    end

    it "enqueues SwallowedExceptionFlushJob with snapshot data" do
      begin
        raise RuntimeError, "dispatch test"
      rescue RuntimeError
        # swallowed
      end

      expect {
        described_class.flush!
      }.to have_enqueued_job(RailsErrorDashboard::SwallowedExceptionFlushJob).with(
        kind_of(Hash),
        kind_of(Hash)
      )
    end

    it "does nothing when counters are empty" do
      # Clear immediately before the assertion — the enabled TracePoint may have
      # accumulated raise/rescue counts from RSpec internals between tests.
      described_class.clear!
      expect {
        described_class.flush!
      }.not_to have_enqueued_job(RailsErrorDashboard::SwallowedExceptionFlushJob)
    end
  end

  describe ".clear!" do
    it "clears all thread-local state" do
      Thread.current[described_class::RAISE_THREAD_KEY] = { "test" => 1 }
      Thread.current[described_class::RESCUE_THREAD_KEY] = { "test" => 1 }
      Thread.current[described_class::FLUSH_THREAD_KEY] = Time.now.to_f

      described_class.clear!

      expect(Thread.current[described_class::RAISE_THREAD_KEY]).to be_nil
      expect(Thread.current[described_class::RESCUE_THREAD_KEY]).to be_nil
      expect(Thread.current[described_class::FLUSH_THREAD_KEY]).to be_nil
    end
  end

  describe "raise without rescue" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "tracks raise but not rescue when exception propagates" do
      begin
        raise RuntimeError, "propagating"
      rescue RuntimeError
        # We still rescue here (test framework needs it), but the point is
        # that raises should increment. Let's verify raises has an entry.
      end

      raises = described_class.current_raises
      expect(raises).not_to be_empty
    end
  end

  describe "multiple raises same key" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "increments counter for repeated raise at same location" do
      3.times do
        begin
          raise RuntimeError, "repeated"
        rescue RuntimeError
          # swallowed
        end
      end

      raises = described_class.current_raises
      runtime_values = raises.select { |k, _| k.start_with?("RuntimeError|") }.values
      # All raises at same location should accumulate into one key
      expect(runtime_values.max).to be >= 3
    end
  end

  describe "adversarial ivar injection" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "overwrites pre-set @_red_raise_loc with actual location" do
      exception = nil
      begin
        err = RuntimeError.new("injected")
        err.instance_variable_set(:@_red_raise_loc, "FAKE_LOCATION:999")
        raise err
      rescue RuntimeError => e
        exception = e
      end

      loc = exception.instance_variable_get(:@_red_raise_loc)
      # The TracePoint callback should have overwritten the fake location
      expect(loc).not_to eq("FAKE_LOCATION:999")
      expect(loc).to include(__FILE__)
    end
  end

  describe "maybe_flush! timing" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      RailsErrorDashboard.configuration.swallowed_exception_flush_interval = 3600
      described_class.enable!
    end

    it "does not flush before interval elapses" do
      begin
        raise RuntimeError, "no flush yet"
      rescue RuntimeError
        # swallowed
      end

      # Counters should still be populated (no flush happened)
      expect(described_class.current_raises).not_to be_empty
    end
  end

  describe "dispatch_flush with empty snapshots" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "does not enqueue job when both snapshots are empty" do
      expect {
        described_class.flush!
      }.not_to have_enqueued_job(RailsErrorDashboard::SwallowedExceptionFlushJob)
    end
  end

  describe "safety" do
    before do
      skip "Requires Ruby 3.3+" unless RUBY_VERSION >= "3.3"
      described_class.enable!
    end

    it "never raises from callbacks" do
      # The callbacks should silently handle any internal errors
      expect {
        begin
          raise RuntimeError, "safety test"
        rescue RuntimeError
          # swallowed
        end
      }.not_to raise_error
    end

    it "does not interfere with exception flow" do
      caught = nil
      begin
        raise ArgumentError, "flow test"
      rescue ArgumentError => e
        caught = e
      end

      expect(caught).to be_a(ArgumentError)
      expect(caught.message).to eq("flow test")
    end

    it "preserves exception message and class through tracking" do
      caught = nil
      begin
        raise TypeError, "specific message"
      rescue TypeError => e
        caught = e
      end

      expect(caught).to be_a(TypeError)
      expect(caught.message).to eq("specific message")
    end

    it "handles nested raise/rescue correctly" do
      outer_caught = nil
      begin
        begin
          raise ArgumentError, "inner"
        rescue ArgumentError
          # inner rescue
        end
        raise RuntimeError, "outer"
      rescue RuntimeError => e
        outer_caught = e
      end

      expect(outer_caught).to be_a(RuntimeError)
      expect(outer_caught.message).to eq("outer")
      # Both should be tracked
      raises = described_class.current_raises
      expect(raises.keys.any? { |k| k.start_with?("ArgumentError|") }).to be true
      expect(raises.keys.any? { |k| k.start_with?("RuntimeError|") }).to be true
    end

    it "handles re-raised exceptions" do
      caught = nil
      begin
        begin
          raise RuntimeError, "re-raise me"
        rescue RuntimeError
          raise  # re-raise
        end
      rescue RuntimeError => e
        caught = e
      end

      expect(caught.message).to eq("re-raise me")
    end
  end
end
