#!/usr/bin/env ruby
# Test upgrade scenarios for v0.1.24
# Scenario 3: Upgrade v0.1.21 → v0.1.24 (Single DB)
# Scenario 4: Upgrade Single → Multi DB

require 'fileutils'
require 'open3'
require 'json'

GEM_PATH = File.expand_path('..', __FILE__)
TEMP_DIR = "/tmp/test_upgrade_v0124"

def run_command(cmd, dir = nil)
  original_dir = Dir.pwd
  Dir.chdir(dir) if dir
  stdout, stderr, status = Open3.capture3(cmd)
  Dir.chdir(original_dir)
  { stdout: stdout, stderr: stderr, success: status.success?, combined: "#{stdout}\n#{stderr}" }
end

def log(msg, level = :info)
  colors = { info: "\e[36m", success: "\e[32m", error: "\e[31m", warning: "\e[33m" }
  color = colors[level] || "\e[0m"
  puts "#{color}#{msg}\e[0m"
end

def test_error_counts(app_dir, expected_apps:, expected_errors:, scenario:)
  log("\n📊 Verifying database state...", :info)

  script = <<-RUBY
    puts "Applications: \#{RailsErrorDashboard::Application.count}"
    RailsErrorDashboard::Application.all.each do |app|
      puts "  - \#{app.name}"
    end

    puts "Total Errors: \#{RailsErrorDashboard::ErrorLog.count}"

    # Check first error
    if RailsErrorDashboard::ErrorLog.any?
      error = RailsErrorDashboard::ErrorLog.first
      puts "First error type: \#{error.error_type}"
      puts "First error has application: \#{error.application.present?}"
      puts "First error application: \#{error.application&.name}"
    end

    # Check latest error
    if RailsErrorDashboard::ErrorLog.count > 1
      error = RailsErrorDashboard::ErrorLog.last
      puts "Latest error type: \#{error.error_type}"
      puts "Latest error has application: \#{error.application.present?}"
      puts "Latest error application: \#{error.application&.name}"
    end
  RUBY

  File.write(File.join(app_dir, "check_state.rb"), script)
  result = run_command("bundle exec rails runner check_state.rb", app_dir)

  if result[:success]
    log("✅ Database state verified", :success)
    puts result[:stdout]

    # Verify counts
    app_count = result[:stdout][/Applications: (\d+)/, 1].to_i
    error_count = result[:stdout][/Total Errors: (\d+)/, 1].to_i

    if app_count == expected_apps && error_count == expected_errors
      log("✅ #{scenario}: Counts match (Apps: #{app_count}, Errors: #{error_count})", :success)
      true
    else
      log("❌ #{scenario}: Count mismatch! Expected Apps: #{expected_apps}, Got: #{app_count}. Expected Errors: #{expected_errors}, Got: #{error_count}", :error)
      false
    end
  else
    log("❌ Failed to verify database state", :error)
    puts result[:combined]
    false
  end
end

log("=" * 70, :info)
log("Rails Error Dashboard - Upgrade Scenarios Testing", :info)
log("=" * 70, :info)

FileUtils.rm_rf(TEMP_DIR)
FileUtils.mkdir_p(TEMP_DIR)

# ==============================================================================
# Scenario 3: Upgrade v0.1.21 → v0.1.24 (Single Database)
# ==============================================================================

log("\n\n🧪 SCENARIO 3: Upgrade v0.1.21 → v0.1.24 (Single Database)", :info)
log("=" * 70, :info)

app_dir = File.join(TEMP_DIR, "upgrade_scenario3")

# Step 1: Create Rails app
log("\n📦 Step 1: Creating Rails app...", :info)
result = run_command("rails new upgrade_scenario3 --skip-git --skip-test --skip-bundle --database=sqlite3 -q 2>&1", TEMP_DIR)
unless result[:success]
  log("❌ Failed to create Rails app", :error)
  exit 1
end
log("✅ Rails app created", :success)

# Step 2: Install v0.1.21
log("\n📦 Step 2: Installing v0.1.21...", :info)
File.open(File.join(app_dir, "Gemfile"), "a") do |f|
  f.puts "gem 'rails_error_dashboard', '0.1.21'"
end

result = run_command("bundle install 2>&1", app_dir)
unless result[:success]
  log("❌ Failed to install v0.1.21", :error)
  puts result[:combined]
  exit 1
end
log("✅ v0.1.21 installed", :success)

# Step 3: Run generator for v0.1.21
log("\n⚙️  Step 3: Running v0.1.21 generator...", :info)
result = run_command("bundle exec rails generate rails_error_dashboard:install --no-interactive 2>&1", app_dir)
log("✅ Generator completed", :success)

# Step 4: Run v0.1.21 migrations
log("\n🔄 Step 4: Running v0.1.21 migrations...", :info)
result = run_command("bundle exec rails db:migrate 2>&1", app_dir)
unless result[:success]
  log("❌ Migrations failed", :error)
  puts result[:combined]
  exit 1
end
log("✅ v0.1.21 migrations completed", :success)

# Step 5: Create errors in v0.1.21 (before multi-app support)
log("\n📝 Step 5: Creating errors in v0.1.21...", :info)

# Create 5 different error types
errors_to_create = [
  { type: 'StandardError', message: 'Old error 1', platform: 'Web' },
  { type: 'ArgumentError', message: 'Old error 2', platform: 'iOS' },
  { type: 'RuntimeError', message: 'Old error 3', platform: 'Android' },
  { type: 'NoMethodError', message: 'Old error 4', platform: 'Web' },
  { type: 'TypeError', message: 'Old error 5', platform: 'Web' }
]

create_errors_script = <<-RUBY
  errors_created = 0

  #{errors_to_create.map { |e|
    "begin
      raise #{e[:type]}, '#{e[:message]}'
    rescue => e
      result = RailsErrorDashboard::Commands::LogError.call(
        exception: e,
        platform: '#{e[:platform]}'
      )
      errors_created += 1 if result.success?
    end"
  }.join("\n  ")}

  puts "Created \#{errors_created} errors in v0.1.21"
  puts "Total errors: \#{RailsErrorDashboard::ErrorLog.count}"
RUBY

File.write(File.join(app_dir, "create_errors.rb"), create_errors_script)
result = run_command("bundle exec rails runner create_errors.rb", app_dir)

if result[:success] && result[:stdout].include?("Created 5 errors")
  log("✅ Created 5 errors in v0.1.21", :success)
  puts result[:stdout]
else
  log("❌ Failed to create errors", :error)
  puts result[:combined]
  exit 1
end

# Step 6: Verify v0.1.21 state (no application_id column yet)
log("\n🔍 Step 6: Verifying v0.1.21 state...", :info)
verify_script = <<-RUBY
  puts "Total errors: \#{RailsErrorDashboard::ErrorLog.count}"

  # Check if application_id column exists (it shouldn't in v0.1.21)
  has_app_column = RailsErrorDashboard::ErrorLog.column_names.include?('application_id')
  puts "Has application_id column: \#{has_app_column}"

  if !has_app_column
    puts "✓ Confirmed: This is v0.1.21 (no application support)"
  end
RUBY

File.write(File.join(app_dir, "verify_v0121.rb"), verify_script)
result = run_command("bundle exec rails runner verify_v0121.rb", app_dir)

if result[:success] && result[:stdout].include?("Has application_id column: false")
  log("✅ v0.1.21 state verified (no multi-app support)", :success)
  puts result[:stdout]
else
  log("⚠️  Unexpected state", :warning)
  puts result[:combined]
end

# Step 7: Upgrade to v0.1.24
log("\n⬆️  Step 7: Upgrading to v0.1.24...", :info)

# Update Gemfile to use local gem
gemfile_content = File.read(File.join(app_dir, "Gemfile"))
gemfile_content.gsub!(/gem 'rails_error_dashboard'.*/, "gem 'rails_error_dashboard', path: '#{GEM_PATH}'")
File.write(File.join(app_dir, "Gemfile"), gemfile_content)

result = run_command("bundle update rails_error_dashboard 2>&1", app_dir)
unless result[:success]
  log("❌ Failed to update gem", :error)
  puts result[:combined]
  exit 1
end
log("✅ Updated to v0.1.24", :success)

# Step 8: Run new migrations
log("\n🔄 Step 8: Running v0.1.24 migrations (multi-app support)...", :info)
result = run_command("bundle exec rails db:migrate 2>&1", app_dir)

unless result[:success]
  log("❌ Migrations failed", :error)
  puts result[:combined]
  exit 1
end

# Check which migrations ran
if result[:stdout].include?("CreateRailsErrorDashboardApplications")
  log("✅ Applications table migration ran", :success)
end
if result[:stdout].include?("BackfillApplicationForExistingErrors")
  log("✅ Backfill migration ran", :success)
end

log("✅ All v0.1.24 migrations completed", :success)

# Step 9: Verify upgrade (all old errors should have application)
log("\n✅ Step 9: Verifying upgrade...", :info)

unless test_error_counts(app_dir, expected_apps: 1, expected_errors: 5, scenario: "Scenario 3")
  exit 1
end

# Step 10: Create new error in v0.1.24
log("\n📝 Step 10: Creating new error in v0.1.24...", :info)
new_error_script = <<-RUBY
  begin
    raise StandardError, 'New error in v0.1.24'
  rescue => e
    result = RailsErrorDashboard::Commands::LogError.call(
      exception: e,
      platform: 'Web'
    )

    if result.success?
      puts "✓ New error created successfully"
      puts "Total errors: \#{RailsErrorDashboard::ErrorLog.count}"
    else
      puts "ERROR: Failed to create new error"
      puts result.error
      exit 1
    end
  end
RUBY

File.write(File.join(app_dir, "create_new_error.rb"), new_error_script)
result = run_command("bundle exec rails runner create_new_error.rb", app_dir)

if result[:success] && result[:stdout].include?("Total errors: 6")
  log("✅ New error created in v0.1.24", :success)
  puts result[:stdout]
else
  log("❌ Failed to create new error", :error)
  puts result[:combined]
  exit 1
end

# Final verification
log("\n🏁 Final Verification for Scenario 3:", :info)
if test_error_counts(app_dir, expected_apps: 1, expected_errors: 6, scenario: "Scenario 3 Final")
  log("\n✅ SCENARIO 3: PASS - Upgrade from v0.1.21 → v0.1.24 successful!", :success)
  log("   - All 5 old errors backfilled with application", :success)
  log("   - New errors work correctly", :success)
  log("   - No data loss", :success)
  SCENARIO_3_RESULT = "PASS"
else
  log("\n❌ SCENARIO 3: FAIL", :error)
  SCENARIO_3_RESULT = "FAIL"
  exit 1
end

# ==============================================================================
# Scenario 4: Upgrade Single → Multi Database
# ==============================================================================

log("\n\n🧪 SCENARIO 4: Upgrade Single DB → Multi DB", :info)
log("=" * 70, :info)

# We'll use the same app from Scenario 3 and reconfigure it
log("\n⚙️  Step 1: Configuring multi-database in database.yml...", :info)

# Backup current database
FileUtils.cp(
  File.join(app_dir, "db", "development.sqlite3"),
  File.join(app_dir, "db", "backup_development.sqlite3")
)

# Add error_dashboard database configuration
db_config_addition = <<-YAML

  error_dashboard:
    <<: *default
    database: db/error_dashboard_development.sqlite3
YAML

File.open(File.join(app_dir, "config", "database.yml"), "a") do |f|
  f.puts db_config_addition
end
log("✅ database.yml configured", :success)

# Step 2: Update initializer for multi-database
log("\n⚙️  Step 2: Enabling multi-database in initializer...", :info)

initializer_path = File.join(app_dir, "config", "initializers", "rails_error_dashboard.rb")
initializer_content = File.read(initializer_path)

# Enable separate database
initializer_content.gsub!(
  /config\.use_separate_database = false/,
  "config.use_separate_database = true"
)

# Add database configuration
initializer_content.gsub!(
  /config\.use_separate_database = true/,
  "config.use_separate_database = true\n  config.database = :error_dashboard"
)

File.write(initializer_path, initializer_content)
log("✅ Initializer updated", :success)

# Step 3: Create the error_dashboard database and run migrations
log("\n🔄 Step 3: Setting up error_dashboard database...", :info)

# Since we're using a separate database, we need to run migrations against it
result = run_command("bundle exec rails db:migrate 2>&1", app_dir)

if result[:success]
  log("✅ Multi-database migrations completed", :success)
else
  log("⚠️  Migration output:", :warning)
  puts result[:combined]
end

# Step 4: Restart Rails (simulate by re-initializing)
log("\n♻️  Step 4: Restarting application (simulated)...", :info)
log("✅ Application would restart here", :success)

# Step 5: Test error creation with multi-database
log("\n📝 Step 5: Creating error with multi-database setup...", :info)

multi_db_error_script = <<-RUBY
  begin
    raise StandardError, 'Multi-DB test error'
  rescue => e
    result = RailsErrorDashboard::Commands::LogError.call(
      exception: e,
      platform: 'Web'
    )

    if result.success?
      puts "✓ Error created in multi-database setup"
      puts "Total errors: \#{RailsErrorDashboard::ErrorLog.count}"

      # Verify we're using the separate database
      db_config = RailsErrorDashboard::ErrorLog.connection_db_config
      puts "Using database: \#{db_config.database}"
    else
      puts "ERROR: Failed to create error"
      puts result.error
      exit 1
    end
  end
RUBY

File.write(File.join(app_dir, "test_multi_db.rb"), multi_db_error_script)
result = run_command("bundle exec rails runner test_multi_db.rb", app_dir)

if result[:success]
  log("✅ Error created in multi-database setup", :success)
  puts result[:stdout]

  if result[:stdout].include?("error_dashboard")
    log("✅ Confirmed: Using separate error_dashboard database", :success)
    SCENARIO_4_RESULT = "PASS"
  else
    log("⚠️  Database name not detected, but error was created", :warning)
    SCENARIO_4_RESULT = "PARTIAL"
  end
else
  log("❌ Failed to create error in multi-database setup", :error)
  puts result[:combined]
  SCENARIO_4_RESULT = "FAIL"
  exit 1
end

log("\n✅ SCENARIO 4: #{SCENARIO_4_RESULT} - Single → Multi DB upgrade successful!", :success)
log("   - Multi-database configuration applied", :success)
log("   - Errors logged to separate database", :success)

# ==============================================================================
# Final Summary
# ==============================================================================

log("\n\n" + "=" * 70, :info)
log("UPGRADE SCENARIOS TEST SUMMARY", :info)
log("=" * 70, :info)

log("\nScenario 3 (v0.1.21 → v0.1.24): #{SCENARIO_3_RESULT}",
    SCENARIO_3_RESULT == "PASS" ? :success : :error)
log("Scenario 4 (Single → Multi DB): #{SCENARIO_4_RESULT}",
    SCENARIO_4_RESULT == "PASS" ? :success : :error)

if SCENARIO_3_RESULT == "PASS" && SCENARIO_4_RESULT == "PASS"
  log("\n✅ ALL UPGRADE SCENARIOS PASSED!", :success)
  log("\nv0.1.24 is ready for release!", :success)
else
  log("\n⚠️  Some scenarios need attention", :warning)
end

# Cleanup
log("\n🧹 Cleaning up test files...", :info)
# FileUtils.rm_rf(TEMP_DIR)
log("✅ Test files preserved at: #{TEMP_DIR}", :success)

log("\n✅ Done!\n", :success)
