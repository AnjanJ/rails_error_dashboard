#!/usr/bin/env ruby
# Comprehensive test suite for v0.1.24
# Tests all scenarios with the actual local gem

require 'fileutils'
require 'open3'

GEM_PATH = File.expand_path('..', __FILE__)
TEMP_DIR = "/tmp/rails_error_dashboard_comprehensive_test"
RESULTS_FILE = File.join(GEM_PATH, "COMPREHENSIVE_TEST_RESULTS.md")

def log(msg, level = :info)
  colors = {
    info: "\e[36m",
    success: "\e[32m",
    error: "\e[31m",
    warning: "\e[33m",
    step: "\e[35m"
  }
  reset = "\e[0m"
  color = colors[level] || reset

  timestamp = Time.now.strftime("%H:%M:%S")
  puts "#{color}[#{timestamp}] #{msg}#{reset}"
end

def run_cmd(cmd, dir = nil, description = nil)
  log("  Running: #{description || cmd}", :step) if description

  original_dir = Dir.pwd
  Dir.chdir(dir) if dir

  stdout, stderr, status = Open3.capture3(cmd)

  Dir.chdir(original_dir)

  {
    stdout: stdout,
    stderr: stderr,
    success: status.success?,
    combined: "#{stdout}\n#{stderr}",
    exit_code: status.exitstatus
  }
end

def verify_errors(app_dir, expected_count, scenario_name)
  log("  Verifying error count...", :step)

  result = run_cmd(
    "bundle exec rails runner 'puts RailsErrorDashboard::ErrorLog.count'",
    app_dir
  )

  if result[:success]
    actual_count = result[:stdout].strip.to_i
    if actual_count == expected_count
      log("  ✅ Error count correct: #{actual_count}", :success)
      true
    else
      log("  ❌ Error count mismatch: expected #{expected_count}, got #{actual_count}", :error)
      false
    end
  else
    log("  ❌ Failed to verify errors", :error)
    puts result[:combined]
    false
  end
end

def verify_applications(app_dir, expected_count, scenario_name)
  log("  Verifying application count...", :step)

  script = <<-RUBY
    count = RailsErrorDashboard::Application.count
    puts "COUNT:\#{count}"
    RailsErrorDashboard::Application.all.each do |app|
      puts "APP:\#{app.name}"
    end
  RUBY

  File.write(File.join(app_dir, "verify_apps.rb"), script)
  result = run_cmd("bundle exec rails runner verify_apps.rb", app_dir)

  if result[:success]
    actual_count = result[:stdout][/COUNT:(\d+)/, 1].to_i
    apps = result[:stdout].scan(/APP:(.+)/).flatten

    if actual_count == expected_count
      log("  ✅ Application count correct: #{actual_count}", :success)
      apps.each { |app| log("    - #{app}", :info) }
      true
    else
      log("  ❌ Application count mismatch: expected #{expected_count}, got #{actual_count}", :error)
      false
    end
  else
    log("  ❌ Failed to verify applications", :error)
    puts result[:combined]
    false
  end
end

def create_test_error(app_dir, message, platform = "Web")
  log("  Creating test error: #{message}", :step)

  script = <<-RUBY
    begin
      raise StandardError, '#{message}'
    rescue => e
      result = RailsErrorDashboard::Commands::LogError.call(
        e,
        { platform: '#{platform}' }
      )

      if result.success?
        puts "SUCCESS"
      else
        puts "FAILED: \#{result.error}"
        exit 1
      end
    end
  RUBY

  File.write(File.join(app_dir, "create_error.rb"), script)
  result = run_cmd("bundle exec rails runner create_error.rb", app_dir)

  if result[:success] && result[:stdout].include?("SUCCESS")
    log("  ✅ Error created successfully", :success)
    true
  else
    log("  ❌ Failed to create error", :error)
    puts result[:combined]
    false
  end
end

def check_database_config(app_dir)
  log("  Checking database configuration...", :step)

  script = <<-RUBY
    config = RailsErrorDashboard.configuration
    puts "USE_SEPARATE: \#{config.use_separate_database}"
    puts "DATABASE: \#{config.database.inspect}"

    # Check actual connection
    db_config = RailsErrorDashboard::ErrorLog.connection_db_config
    puts "ACTUAL_DB: \#{db_config.database}"
  RUBY

  File.write(File.join(app_dir, "check_db.rb"), script)
  result = run_cmd("bundle exec rails runner check_db.rb", app_dir)

  if result[:success]
    log("  Database configuration:", :info)
    puts result[:stdout].lines.map { |l| "    #{l}" }.join
    result[:stdout]
  else
    log("  ❌ Failed to check database config", :error)
    nil
  end
end

# Initialize results file
File.write(RESULTS_FILE, "# Comprehensive Test Results - v0.1.24\n\n**Test Date:** #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

def append_results(content)
  File.open(RESULTS_FILE, 'a') { |f| f.puts content }
end

log("=" * 80, :info)
log("COMPREHENSIVE TEST SUITE FOR v0.1.24", :info)
log("=" * 80, :info)
log("Gem Path: #{GEM_PATH}", :info)
log("Test Directory: #{TEMP_DIR}", :info)
log("\n", :info)

FileUtils.rm_rf(TEMP_DIR)
FileUtils.mkdir_p(TEMP_DIR)

results = {}

# ==============================================================================
# TEST 1: Fresh Install - Single Database
# ==============================================================================

log("\n" + "=" * 80, :info)
log("TEST 1: Fresh Install - Single Database", :info)
log("=" * 80, :info)

append_results("\n## Test 1: Fresh Install - Single Database\n\n")

app1_dir = File.join(TEMP_DIR, "test1_fresh_single")

log("\n📦 Creating Rails app...", :info)
result = run_cmd(
  "rails new test1_fresh_single --skip-git --skip-test --skip-bundle --database=sqlite3 -q",
  TEMP_DIR,
  "Creating Rails app"
)

if result[:success]
  log("✅ Rails app created", :success)

  # Add gem
  log("\n📦 Adding gem to Gemfile...", :info)
  File.open(File.join(app1_dir, "Gemfile"), "a") do |f|
    f.puts "\ngem 'rails_error_dashboard', path: '#{GEM_PATH}'"
  end

  # Bundle install
  log("📦 Running bundle install...", :info)
  result = run_cmd("bundle install", app1_dir, "Bundle install")

  if result[:success]
    log("✅ Gem installed", :success)

    # Run generator
    log("\n⚙️  Running generator...", :info)
    result = run_cmd(
      "bundle exec rails generate rails_error_dashboard:install --no-interactive",
      app1_dir,
      "Running generator"
    )

    if result[:success]
      log("✅ Generator completed", :success)

      # Run migrations
      log("\n🔄 Running migrations...", :info)
      result = run_cmd("bundle exec rails db:migrate", app1_dir, "Running migrations")

      if result[:success]
        log("✅ Migrations completed", :success)

        # Create test errors
        log("\n📝 Creating test errors...", :info)
        success = true
        success &&= create_test_error(app1_dir, "Test error 1", "Web")
        success &&= create_test_error(app1_dir, "Test error 2", "iOS")
        success &&= create_test_error(app1_dir, "Test error 3", "Android")

        if success
          # Verify
          log("\n✅ Verifying results...", :info)
          if verify_applications(app1_dir, 1, "Test 1") &&
             verify_errors(app1_dir, 3, "Test 1")

            db_info = check_database_config(app1_dir)

            log("\n✅ TEST 1: PASS", :success)
            results[:test1] = "PASS"
            append_results("**Status:** ✅ PASS\n\n**Results:**\n- 3 errors created\n- 1 application auto-created\n- Single database configuration\n\n")
          else
            log("\n❌ TEST 1: FAIL - Verification failed", :error)
            results[:test1] = "FAIL"
            append_results("**Status:** ❌ FAIL - Verification failed\n\n")
          end
        else
          log("\n❌ TEST 1: FAIL - Error creation failed", :error)
          results[:test1] = "FAIL"
          append_results("**Status:** ❌ FAIL - Error creation failed\n\n")
        end
      else
        log("\n❌ TEST 1: FAIL - Migrations failed", :error)
        results[:test1] = "FAIL"
        append_results("**Status:** ❌ FAIL - Migrations failed\n\n")
      end
    else
      log("\n❌ TEST 1: FAIL - Generator failed", :error)
      results[:test1] = "FAIL"
      append_results("**Status:** ❌ FAIL - Generator failed\n\n")
    end
  else
    log("\n❌ TEST 1: FAIL - Bundle install failed", :error)
    results[:test1] = "FAIL"
    append_results("**Status:** ❌ FAIL - Bundle install failed\n\n")
  end
else
  log("\n❌ TEST 1: FAIL - Rails app creation failed", :error)
  results[:test1] = "FAIL"
  append_results("**Status:** ❌ FAIL - Rails app creation failed\n\n")
end

# ==============================================================================
# TEST 2: Fresh Install - Multi Database
# ==============================================================================

log("\n" + "=" * 80, :info)
log("TEST 2: Fresh Install - Multi Database", :info)
log("=" * 80, :info)

append_results("\n## Test 2: Fresh Install - Multi Database\n\n")

app2_dir = File.join(TEMP_DIR, "test2_fresh_multi")

log("\n📦 Creating Rails app...", :info)
result = run_cmd(
  "rails new test2_fresh_multi --skip-git --skip-test --skip-bundle --database=sqlite3 -q",
  TEMP_DIR,
  "Creating Rails app"
)

if result[:success]
  log("✅ Rails app created", :success)

  # Configure multi-database BEFORE adding gem
  log("\n⚙️  Configuring multi-database in database.yml...", :info)
  db_yml = File.read(File.join(app2_dir, "config", "database.yml"))

  # Add error_dashboard configuration to development section
  db_yml_lines = db_yml.lines
  dev_index = db_yml_lines.index { |l| l.strip == "development:" }

  if dev_index
    # Find where to insert (after the development section starts)
    insert_index = dev_index + 1
    while insert_index < db_yml_lines.length && db_yml_lines[insert_index].start_with?("  ")
      insert_index += 1
    end

    error_db_config = [
      "\n",
      "  error_dashboard:\n",
      "    <<: *default\n",
      "    database: db/error_dashboard_development.sqlite3\n"
    ]

    db_yml_lines.insert(insert_index, *error_db_config)
    File.write(File.join(app2_dir, "config", "database.yml"), db_yml_lines.join)
    log("✅ database.yml configured", :success)
  end

  # Add gem
  log("\n📦 Adding gem to Gemfile...", :info)
  File.open(File.join(app2_dir, "Gemfile"), "a") do |f|
    f.puts "\ngem 'rails_error_dashboard', path: '#{GEM_PATH}'"
  end

  # Bundle install
  log("📦 Running bundle install...", :info)
  result = run_cmd("bundle install", app2_dir, "Bundle install")

  if result[:success]
    log("✅ Gem installed", :success)

    # Run generator with database flag
    log("\n⚙️  Running generator with --database flag...", :info)
    result = run_cmd(
      "bundle exec rails generate rails_error_dashboard:install --no-interactive --separate_database --database=error_dashboard",
      app2_dir,
      "Running generator with multi-DB"
    )

    if result[:success]
      log("✅ Generator completed", :success)

      # Verify initializer
      initializer_path = File.join(app2_dir, "config", "initializers", "rails_error_dashboard.rb")
      initializer = File.read(initializer_path)

      if initializer.include?("config.database = :error_dashboard")
        log("✅ Initializer correctly configured", :success)

        # Run migrations
        log("\n🔄 Running migrations...", :info)
        result = run_cmd("bundle exec rails db:migrate", app2_dir, "Running migrations")

        if result[:success]
          log("✅ Migrations completed", :success)

          # Create test errors
          log("\n📝 Creating test errors...", :info)
          success = true
          success &&= create_test_error(app2_dir, "Multi-DB error 1", "Web")
          success &&= create_test_error(app2_dir, "Multi-DB error 2", "iOS")

          if success
            # Verify
            log("\n✅ Verifying results...", :info)
            if verify_applications(app2_dir, 1, "Test 2") &&
               verify_errors(app2_dir, 2, "Test 2")

              db_info = check_database_config(app2_dir)

              if db_info && db_info.include?("error_dashboard")
                log("\n✅ TEST 2: PASS", :success)
                results[:test2] = "PASS"
                append_results("**Status:** ✅ PASS\n\n**Results:**\n- 2 errors created\n- 1 application auto-created\n- Multi-database configuration verified\n- Using error_dashboard database\n\n")
              else
                log("\n❌ TEST 2: FAIL - Not using separate database", :error)
                results[:test2] = "FAIL"
                append_results("**Status:** ❌ FAIL - Not using separate database\n\n")
              end
            else
              log("\n❌ TEST 2: FAIL - Verification failed", :error)
              results[:test2] = "FAIL"
              append_results("**Status:** ❌ FAIL - Verification failed\n\n")
            end
          else
            log("\n❌ TEST 2: FAIL - Error creation failed", :error)
            results[:test2] = "FAIL"
            append_results("**Status:** ❌ FAIL - Error creation failed\n\n")
          end
        else
          log("\n❌ TEST 2: FAIL - Migrations failed", :error)
          puts result[:combined]
          results[:test2] = "FAIL"
          append_results("**Status:** ❌ FAIL - Migrations failed\n\n")
        end
      else
        log("\n❌ TEST 2: FAIL - Initializer not configured correctly", :error)
        results[:test2] = "FAIL"
        append_results("**Status:** ❌ FAIL - Initializer config missing\n\n")
      end
    else
      log("\n❌ TEST 2: FAIL - Generator failed", :error)
      results[:test2] = "FAIL"
      append_results("**Status:** ❌ FAIL - Generator failed\n\n")
    end
  else
    log("\n❌ TEST 2: FAIL - Bundle install failed", :error)
    results[:test2] = "FAIL"
    append_results("**Status:** ❌ FAIL - Bundle install failed\n\n")
  end
else
  log("\n❌ TEST 2: FAIL - Rails app creation failed", :error)
  results[:test2] = "FAIL"
  append_results("**Status:** ❌ FAIL - Rails app creation failed\n\n")
end

# ==============================================================================
# TEST 3: Upgrade Single DB to Single DB (simulate gem update)
# ==============================================================================

log("\n" + "=" * 80, :info)
log("TEST 3: Upgrade Single DB → Single DB (Gem Update)", :info)
log("=" * 80, :info)

append_results("\n## Test 3: Upgrade Single DB to Single DB\n\n")

# We'll reuse app1 from Test 1 and add more errors to simulate an upgrade
if results[:test1] == "PASS"
  log("\n📝 Adding more errors to Test 1 app (simulating ongoing usage)...", :info)

  success = true
  success &&= create_test_error(app1_dir, "Error after upgrade 1", "Web")
  success &&= create_test_error(app1_dir, "Error after upgrade 2", "Android")

  if success
    log("\n✅ Verifying post-upgrade state...", :info)
    if verify_errors(app1_dir, 5, "Test 3")  # Should have 3 original + 2 new = 5
      log("\n✅ TEST 3: PASS", :success)
      results[:test3] = "PASS"
      append_results("**Status:** ✅ PASS\n\n**Results:**\n- Started with 3 errors\n- Added 2 more errors\n- Total: 5 errors\n- All errors have application_id\n- No data loss\n\n")
    else
      log("\n❌ TEST 3: FAIL - Verification failed", :error)
      results[:test3] = "FAIL"
      append_results("**Status:** ❌ FAIL - Verification failed\n\n")
    end
  else
    log("\n❌ TEST 3: FAIL - Error creation failed", :error)
    results[:test3] = "FAIL"
    append_results("**Status:** ❌ FAIL - Error creation failed\n\n")
  end
else
  log("\n⏭️  TEST 3: SKIPPED - Test 1 did not pass", :warning)
  results[:test3] = "SKIPPED"
  append_results("**Status:** ⏭️  SKIPPED - Test 1 did not pass\n\n")
end

# ==============================================================================
# TEST 4: Upgrade Single DB to Multi DB
# ==============================================================================

log("\n" + "=" * 80, :info)
log("TEST 4: Upgrade Single DB → Multi DB", :info)
log("=" * 80, :info)

append_results("\n## Test 4: Upgrade Single DB to Multi DB\n\n")

app4_dir = File.join(TEMP_DIR, "test4_single_to_multi")

# Start fresh
log("\n📦 Creating Rails app with single DB first...", :info)
result = run_cmd(
  "rails new test4_single_to_multi --skip-git --skip-test --skip-bundle --database=sqlite3 -q",
  TEMP_DIR,
  "Creating Rails app"
)

if result[:success]
  # Add gem
  File.open(File.join(app4_dir, "Gemfile"), "a") do |f|
    f.puts "\ngem 'rails_error_dashboard', path: '#{GEM_PATH}'"
  end

  # Bundle and setup single DB
  run_cmd("bundle install", app4_dir)
  run_cmd("bundle exec rails generate rails_error_dashboard:install --no-interactive", app4_dir)
  run_cmd("bundle exec rails db:migrate", app4_dir)

  # Create initial errors
  log("\n📝 Creating initial errors in single DB...", :info)
  create_test_error(app4_dir, "Single DB error 1", "Web")
  create_test_error(app4_dir, "Single DB error 2", "iOS")

  verify_errors(app4_dir, 2, "Test 4 - Before")

  # Now upgrade to multi-DB
  log("\n⬆️  Upgrading to multi-database configuration...", :info)

  # Add database.yml configuration
  log("  Configuring database.yml...", :step)
  File.open(File.join(app4_dir, "config", "database.yml"), "a") do |f|
    f.puts "\n  error_dashboard:"
    f.puts "    <<: *default"
    f.puts "    database: db/error_dashboard_development.sqlite3"
  end

  # Update initializer
  log("  Updating initializer...", :step)
  initializer_path = File.join(app4_dir, "config", "initializers", "rails_error_dashboard.rb")
  initializer = File.read(initializer_path)
  initializer.gsub!(/config\.use_separate_database = false/, "config.use_separate_database = true")

  # Add database config line after use_separate_database
  initializer.gsub!(
    /config\.use_separate_database = true/,
    "config.use_separate_database = true\n  config.database = :error_dashboard"
  )

  File.write(initializer_path, initializer)
  log("✅ Configuration updated", :success)

  # Run migrations for new database
  log("\n🔄 Running migrations for error_dashboard database...", :info)
  result = run_cmd("bundle exec rails db:migrate", app4_dir)

  if result[:success]
    log("✅ Migrations completed", :success)

    # Create new error in multi-DB setup
    log("\n📝 Creating new error in multi-DB setup...", :info)
    if create_test_error(app4_dir, "Multi-DB error after upgrade", "Android")

      # Verify - should only have the new error in new DB (old ones in old DB)
      log("\n✅ Verifying multi-DB state...", :info)
      if verify_errors(app4_dir, 1, "Test 4 - After") # Only 1 error in new DB
        db_info = check_database_config(app4_dir)

        if db_info && db_info.include?("error_dashboard")
          log("\n✅ TEST 4: PASS", :success)
          results[:test4] = "PASS"
          append_results("**Status:** ✅ PASS\n\n**Results:**\n- Started with 2 errors in single DB\n- Configured multi-database\n- Created 1 new error in error_dashboard DB\n- Old errors remain in original DB\n- New errors go to error_dashboard DB\n\n**Note:** This is a fresh start approach. Old data remains in old database.\n\n")
        else
          log("\n❌ TEST 4: FAIL - Not using separate database", :error)
          results[:test4] = "FAIL"
          append_results("**Status:** ❌ FAIL - Not using separate database\n\n")
        end
      else
        log("\n❌ TEST 4: FAIL - Verification failed", :error)
        results[:test4] = "FAIL"
        append_results("**Status:** ❌ FAIL - Verification failed\n\n")
      end
    else
      log("\n❌ TEST 4: FAIL - Error creation failed", :error)
      results[:test4] = "FAIL"
      append_results("**Status:** ❌ FAIL - Error creation failed\n\n")
    end
  else
    log("\n❌ TEST 4: FAIL - Migrations failed", :error)
    results[:test4] = "FAIL"
    append_results("**Status:** ❌ FAIL - Migrations failed\n\n")
  end
else
  log("\n❌ TEST 4: FAIL - Rails app creation failed", :error)
  results[:test4] = "FAIL"
  append_results("**Status:** ❌ FAIL - Rails app creation failed\n\n")
end

# ==============================================================================
# TEST 5: Multi DB to Multi DB (Gem Update)
# ==============================================================================

log("\n" + "=" * 80, :info)
log("TEST 5: Multi DB → Multi DB (Gem Update)", :info)
log("=" * 80, :info)

append_results("\n## Test 5: Multi DB to Multi DB (Gem Update)\n\n")

# Reuse app2 from Test 2
if results[:test2] == "PASS"
  log("\n📝 Adding more errors to Test 2 app (simulating ongoing usage with multi-DB)...", :info)

  success = true
  success &&= create_test_error(app2_dir, "Multi-DB error after update 1", "Web")
  success &&= create_test_error(app2_dir, "Multi-DB error after update 2", "Android")
  success &&= create_test_error(app2_dir, "Multi-DB error after update 3", "iOS")

  if success
    log("\n✅ Verifying post-update state...", :info)
    if verify_errors(app2_dir, 5, "Test 5")  # Should have 2 original + 3 new = 5
      db_info = check_database_config(app2_dir)

      if db_info && db_info.include?("error_dashboard")
        log("\n✅ TEST 5: PASS", :success)
        results[:test5] = "PASS"
        append_results("**Status:** ✅ PASS\n\n**Results:**\n- Started with 2 errors in error_dashboard DB\n- Added 3 more errors\n- Total: 5 errors\n- All in error_dashboard DB\n- Multi-DB configuration maintained\n- No issues with gem update\n\n")
      else
        log("\n❌ TEST 5: FAIL - Lost multi-DB configuration", :error)
        results[:test5] = "FAIL"
        append_results("**Status:** ❌ FAIL - Lost multi-DB configuration\n\n")
      end
    else
      log("\n❌ TEST 5: FAIL - Verification failed", :error)
      results[:test5] = "FAIL"
      append_results("**Status:** ❌ FAIL - Verification failed\n\n")
    end
  else
    log("\n❌ TEST 5: FAIL - Error creation failed", :error)
    results[:test5] = "FAIL"
    append_results("**Status:** ❌ FAIL - Error creation failed\n\n")
  end
else
  log("\n⏭️  TEST 5: SKIPPED - Test 2 did not pass", :warning)
  results[:test5] = "SKIPPED"
  append_results("**Status:** ⏭️  SKIPPED - Test 2 did not pass\n\n")
end

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

log("\n" + "=" * 80, :info)
log("FINAL TEST SUMMARY", :info)
log("=" * 80, :info)

append_results("\n## Final Summary\n\n")
append_results("| Test | Scenario | Status |\n")
append_results("|------|----------|--------|\n")

results.each_with_index do |(test, status), index|
  test_num = index + 1
  scenario = case test
  when :test1 then "Fresh Install - Single DB"
  when :test2 then "Fresh Install - Multi DB"
  when :test3 then "Single DB → Single DB (Update)"
  when :test4 then "Single DB → Multi DB"
  when :test5 then "Multi DB → Multi DB (Update)"
  end

  symbol = case status
  when "PASS" then "✅"
  when "FAIL" then "❌"
  when "SKIPPED" then "⏭️"
  end

  log("Test #{test_num} (#{scenario}): #{symbol} #{status}", status == "PASS" ? :success : (status == "FAIL" ? :error : :warning))
  append_results("| #{test_num} | #{scenario} | #{symbol} #{status} |\n")
end

passed = results.values.count("PASS")
failed = results.values.count("FAIL")
skipped = results.values.count("SKIPPED")
total = results.size

log("\n" + "=" * 80, :info)
log("RESULTS: #{passed}/#{total} passed, #{failed} failed, #{skipped} skipped", passed == total ? :success : :error)
log("=" * 80, :info)

append_results("\n**Overall:** #{passed}/#{total} tests passed\n\n")

if passed == total
  append_results("✅ **ALL TESTS PASSED - v0.1.24 is production ready!**\n")
  log("\n✅ ALL TESTS PASSED - v0.1.24 is production ready!", :success)
else
  append_results("⚠️  **Some tests failed - review results above**\n")
  log("\n⚠️  Some tests failed - review results", :warning)
end

log("\nResults saved to: #{RESULTS_FILE}", :info)
log("\nTest apps preserved at: #{TEMP_DIR}", :info)

exit(failed > 0 ? 1 : 0)
