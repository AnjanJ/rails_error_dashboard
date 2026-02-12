# frozen_string_literal: true

# ============================================================================
# Pre-Release Test Harness
# Shared assertion framework for chaos test scripts
# Used by: rails runner test/pre_release/chaos/phase_*.rb
# ============================================================================

module PreReleaseTestHarness
  PASS_COUNT = [ 0 ]
  FAIL_COUNT = [ 0 ]

  def self.assert(label, condition, detail = nil)
    if condition
      $stdout.puts "  \u2713 #{label}"
      PASS_COUNT[0] += 1
    else
      $stdout.puts "  \u2717 FAIL: #{label}#{detail ? " — #{detail}" : ""}"
      FAIL_COUNT[0] += 1
    end
  end

  def self.assert_no_crash(label)
    result = yield
    $stdout.puts "  \u2713 #{label}"
    PASS_COUNT[0] += 1
    result
  rescue => e
    $stdout.puts "  \u2717 FAIL: #{label} — #{e.class}: #{e.message}"
    $stdout.puts "    #{e.backtrace&.first(3)&.join("\n    ")}"
    FAIL_COUNT[0] += 1
    nil
  end

  def self.assert_http(label, status, expected_range = 200..399)
    if status.is_a?(Integer) && expected_range.include?(status)
      $stdout.puts "  \u2713 #{label} → #{status}"
      PASS_COUNT[0] += 1
    else
      $stdout.puts "  \u2717 FAIL: #{label} → #{status} (expected #{expected_range})"
      FAIL_COUNT[0] += 1
    end
  end

  def self.section(title)
    puts "--- #{title} ---"
  end

  def self.header(title)
    puts "=" * 70
    puts title
    puts "=" * 70
    puts ""
  end

  def self.summary(phase_name)
    puts ""
    puts "=" * 70
    puts "#{phase_name} RESULTS: #{PASS_COUNT[0]} passed, #{FAIL_COUNT[0]} failed"
    puts "=" * 70
    FAIL_COUNT[0] > 0 ? 1 : 0
  end

  def self.reset!
    PASS_COUNT[0] = 0
    FAIL_COUNT[0] = 0
  end

  def self.passed
    PASS_COUNT[0]
  end

  def self.failed
    FAIL_COUNT[0]
  end
end

# Convenience aliases for use in test scripts
def assert(label, condition, detail = nil)
  PreReleaseTestHarness.assert(label, condition, detail)
end

def assert_no_crash(label, &block)
  PreReleaseTestHarness.assert_no_crash(label, &block)
end

def assert_http(label, status, expected_range = 200..399)
  PreReleaseTestHarness.assert_http(label, status, expected_range)
end

# Helper: Log an error and return the ErrorLog record
# Handles both sync (returns ErrorLog) and async (returns job, need to look up record)
def log_error_and_find(exception, context = {})
  result = RailsErrorDashboard::Commands::LogError.call(exception, context)

  # In sync mode, result IS the ErrorLog
  return result if result.is_a?(RailsErrorDashboard::ErrorLog)

  # In async mode with inline adapter, the job already ran but returned the job instance.
  # Look up the most recently created error matching this exception.
  RailsErrorDashboard::ErrorLog
    .where(error_type: exception.class.name)
    .order(id: :desc)
    .first
end

# Helper: Find the most recent ErrorLog for a given error type
def find_captured_error(error_type)
  RailsErrorDashboard::ErrorLog
    .where(error_type: error_type)
    .order(id: :desc)
    .first
end

# Helper: Assert an error was captured via subscriber with expected attributes
# Reports an error via Rails.error.report and verifies the ErrorLog record
def assert_error_captured(error_class, message, expected_severity:, context: {})
  label = error_class.name

  count_before = RailsErrorDashboard::ErrorLog.where(error_type: error_class.name).count

  begin
    raise error_class, message
  rescue Exception => e
    Rails.error.report(e, handled: false, severity: :error, context: context)
  end

  error_log = find_captured_error(error_class.name)
  count_after = RailsErrorDashboard::ErrorLog.where(error_type: error_class.name).count

  assert "#{label}: captured (record created)", count_after > count_before,
    "count unchanged: #{count_before} -> #{count_after}"

  if error_log
    assert "#{label}: error_type correct", error_log.error_type == error_class.name
    assert "#{label}: severity is #{expected_severity}", error_log.severity.to_sym == expected_severity,
      "got #{error_log.severity}"
    assert "#{label}: message present", error_log.message.present?
    assert "#{label}: backtrace present", error_log.backtrace.present?
    assert "#{label}: error_hash is 16-char hex", error_log.error_hash&.match?(/\A[0-9a-f]{16}\z/)
  end
end
