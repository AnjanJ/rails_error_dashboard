# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Backtrace Limiting", type: :integration do
  before do
    # Reset to defaults first to avoid inheriting dummy app's config (max_backtrace_lines = 50)
    RailsErrorDashboard.reset_configuration!
    # Ensure async_logging is disabled for these tests since we need synchronous error logs
    RailsErrorDashboard.configure do |config|
      config.async_logging = false
    end
  end

  after do
    RailsErrorDashboard.reset_configuration!
  end

  describe "with default max_backtrace_lines (100)" do
    it "stores full backtrace when under limit" do
      error = StandardError.new("Short backtrace")
      error.set_backtrace(10.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(error_log.backtrace.lines.count).to eq(10)
      expect(error_log.backtrace).not_to include("truncated")
    end

    it "truncates backtrace when over limit" do
      error = StandardError.new("Long backtrace")
      error.set_backtrace(200.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      # Should have exactly 100 lines plus truncation notice
      lines = error_log.backtrace.lines
      expect(lines.count).to eq(101)  # 100 lines + 1 truncation notice
      expect(error_log.backtrace).to include("... (100 more lines truncated)")
    end

    it "includes first 100 lines when truncating" do
      error = StandardError.new("Long backtrace")
      backtrace_lines = 200.times.map { |i| "line_#{i}.rb:#{i}" }
      error.set_backtrace(backtrace_lines)

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      # Verify first line is included
      expect(error_log.backtrace).to include("line_0.rb:0")
      # Verify 99th line is included
      expect(error_log.backtrace).to include("line_99.rb:99")
      # Verify 100th line is NOT included (truncated)
      expect(error_log.backtrace).not_to include("line_100.rb:100")
    end
  end

  describe "with custom max_backtrace_lines" do
    before do
      RailsErrorDashboard.configure do |config|
        config.max_backtrace_lines = 10
      end
    end

    it "respects custom limit" do
      error = StandardError.new("Custom limit")
      error.set_backtrace(50.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      # Should have 10 lines + truncation notice
      lines = error_log.backtrace.lines
      expect(lines.count).to eq(11)
      expect(error_log.backtrace).to include("... (40 more lines truncated)")
    end

    it "includes correct truncation count" do
      error = StandardError.new("Truncation count test")
      error.set_backtrace(100.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      # 100 total - 10 kept = 90 truncated
      expect(error_log.backtrace).to include("... (90 more lines truncated)")
    end
  end

  describe "with max_backtrace_lines = 0" do
    before do
      RailsErrorDashboard.configure do |config|
        config.max_backtrace_lines = 0
      end
    end

    it "stores empty backtrace with truncation notice" do
      error = StandardError.new("Zero limit")
      error.set_backtrace(10.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(error_log.backtrace).to eq("... (10 more lines truncated)")
    end
  end

  describe "with very large max_backtrace_lines" do
    before do
      RailsErrorDashboard.configure do |config|
        config.max_backtrace_lines = 10000
      end
    end

    it "stores full backtrace when under high limit" do
      error = StandardError.new("High limit")
      error.set_backtrace(100.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(error_log.backtrace.lines.count).to eq(100)
      expect(error_log.backtrace).not_to include("truncated")
    end
  end

  describe "edge cases" do
    it "handles nil backtrace" do
      error = StandardError.new("No backtrace")
      error.set_backtrace(nil)

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(error_log.backtrace).to be_nil
    end

    it "handles empty backtrace array" do
      error = StandardError.new("Empty backtrace")
      error.set_backtrace([])

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      expect(error_log.backtrace).to eq("")
      expect(error_log.backtrace).not_to include("truncated")
    end

    it "handles backtrace with exactly max_lines" do
      error = StandardError.new("Exact limit")
      error.set_backtrace(100.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      # Exactly 100 lines, no truncation
      expect(error_log.backtrace.lines.count).to eq(100)
      expect(error_log.backtrace).not_to include("truncated")
    end

    it "handles backtrace with max_lines + 1" do
      error = StandardError.new("One over limit")
      error.set_backtrace(101.times.map { |i| "line_#{i}.rb:#{i}" })

      error_log = RailsErrorDashboard::Commands::LogError.call(error, {})

      # 100 lines + truncation notice
      expect(error_log.backtrace.lines.count).to eq(101)
      expect(error_log.backtrace).to include("... (1 more lines truncated)")
    end
  end

  describe "performance impact" do
    it "reduces database storage for large backtraces" do
      # Create error with massive backtrace
      large_error = StandardError.new("Huge backtrace")
      large_error.set_backtrace(1000.times.map { |i| "line_#{i}.rb:#{i}" })

      # Create error with small backtrace
      small_error = StandardError.new("Small backtrace")
      small_error.set_backtrace(10.times.map { |i| "line_#{i}.rb:#{i}" })

      large_log = RailsErrorDashboard::Commands::LogError.call(large_error, {})
      small_log = RailsErrorDashboard::Commands::LogError.call(small_error, {})

      # Large backtrace should be truncated to similar size as small one
      # (100 lines vs 10 lines, not 1000 vs 10)
      large_size = large_log.backtrace.bytesize
      small_size = small_log.backtrace.bytesize

      # Large should be less than 15x the small (not 100x)
      # 100 lines vs 10 lines = 10x, add buffer for truncation message
      expect(large_size).to be < (small_size * 15)
    end

    it "logs thousands of errors quickly with truncation" do
      errors = 100.times.map do |i|
        error = StandardError.new("Error #{i}")
        error.set_backtrace(500.times.map { |j| "line_#{j}.rb:#{j}" })
        error
      end

      start_time = Time.now

      errors.each do |error|
        RailsErrorDashboard::Commands::LogError.call(error, {})
      end

      elapsed = Time.now - start_time

      # Should complete in reasonable time (< 5 seconds for 100 errors)
      expect(elapsed).to be < 5
    end
  end

  describe "interaction with async logging" do
    before do
      RailsErrorDashboard.configure do |config|
        config.async_logging = true
        config.async_adapter = :async
        config.max_backtrace_lines = 20
      end
    end

    it "truncates backtrace before serializing for async job" do
      error = StandardError.new("Async truncation")
      error.set_backtrace(100.times.map { |i| "line_#{i}.rb:#{i}" })

      # Enqueue the job
      RailsErrorDashboard::Commands::LogError.call(error, {})

      # Perform enqueued jobs
      perform_enqueued_jobs

      error_log = RailsErrorDashboard::ErrorLog.last

      # Should have 20 lines + truncation notice
      expect(error_log.backtrace.lines.count).to eq(21)
      expect(error_log.backtrace).to include("... (80 more lines truncated)")
    end
  end

  describe "deduplication with truncated backtraces" do
    it "deduplicates errors with same truncated backtrace" do
      # Create two errors with same beginning but different endings
      backtrace1 = 100.times.map { |i| i < 50 ? "common_#{i}.rb:#{i}" : "unique1_#{i}.rb:#{i}" }
      backtrace2 = 100.times.map { |i| i < 50 ? "common_#{i}.rb:#{i}" : "unique2_#{i}.rb:#{i}" }

      error1 = StandardError.new("Same error")
      error1.set_backtrace(backtrace1)

      error2 = StandardError.new("Same error")
      error2.set_backtrace(backtrace2)

      # Log both errors
      log1 = RailsErrorDashboard::Commands::LogError.call(error1, {})
      log2 = RailsErrorDashboard::Commands::LogError.call(error2, {})

      # Should be deduplicated (same first 50 lines)
      expect(log1.id).to eq(log2.id)
      expect(log2.occurrence_count).to eq(2)
    end
  end
end
