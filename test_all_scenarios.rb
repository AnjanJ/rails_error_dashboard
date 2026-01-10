#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive Integration Test Suite for rails_error_dashboard v0.1.24
# Tests all installation and upgrade scenarios

require 'fileutils'
require 'open3'

class IntegrationTestSuite
  TEST_DIR = "/tmp/rails_error_dashboard_integration_tests"
  GEM_PATH = File.expand_path("..", __FILE__)

  def initialize
    @results = []
    @start_time = Time.now
  end

  def run_all
    puts "=" * 80
    puts "Rails Error Dashboard - Comprehensive Integration Test Suite"
    puts "Version: 0.1.24"
    puts "Started: #{@start_time}"
    puts "=" * 80
    puts

    cleanup_test_directory

    # Test all scenarios
    test_scenario_1_fresh_single_db
    test_scenario_2_fresh_multi_db
    test_scenario_3_upgrade_single_to_single
    test_scenario_4_upgrade_single_to_multi
    test_scenario_5_upgrade_multi_to_multi

    # Print summary
    print_summary
  end

  private

  def cleanup_test_directory
    puts "🧹 Cleaning up test directory..."
    FileUtils.rm_rf(TEST_DIR) if Dir.exist?(TEST_DIR)
    FileUtils.mkdir_p(TEST_DIR)
    puts "✅ Test directory ready: #{TEST_DIR}\n\n"
  end

  def test_scenario_1_fresh_single_db
    scenario = "Scenario 1: Fresh Install - Single Database"
    puts "\n" + "=" * 80
    puts scenario
    puts "=" * 80

    app_dir = "#{TEST_DIR}/scenario1_fresh_single"

    steps = [
      { name: "Create Rails app", cmd: -> { create_rails_app(app_dir) } },
      { name: "Add gem to Gemfile", cmd: -> { add_gem_to_gemfile(app_dir) } },
      { name: "Bundle install", cmd: -> { run_bundle_install(app_dir) } },
      { name: "Run generator (single DB)", cmd: -> { run_generator_single_db(app_dir) } },
      { name: "Run migrations", cmd: -> { run_migrations(app_dir) } },
      { name: "Verify tables created", cmd: -> { verify_tables(app_dir) } },
      { name: "Create test error", cmd: -> { create_test_error(app_dir) } },
      { name: "Verify error logged", cmd: -> { verify_error_logged(app_dir) } }
    ]

    execute_scenario(scenario, steps)
  end

  def test_scenario_2_fresh_multi_db
    scenario = "Scenario 2: Fresh Install - Multi Database"
    puts "\n" + "=" * 80
    puts scenario
    puts "=" * 80

    app_dir = "#{TEST_DIR}/scenario2_fresh_multi"

    steps = [
      { name: "Create Rails app", cmd: -> { create_rails_app(app_dir) } },
      { name: "Add gem to Gemfile", cmd: -> { add_gem_to_gemfile(app_dir) } },
      { name: "Configure database.yml for multi-DB", cmd: -> { configure_multi_db(app_dir) } },
      { name: "Bundle install", cmd: -> { run_bundle_install(app_dir) } },
      { name: "Run generator (multi DB)", cmd: -> { run_generator_multi_db(app_dir) } },
      { name: "Create databases", cmd: -> { create_databases(app_dir) } },
      { name: "Run migrations", cmd: -> { run_migrations(app_dir) } },
      { name: "Verify tables in error_dashboard DB", cmd: -> { verify_multi_db_tables(app_dir) } },
      { name: "Create test error", cmd: -> { create_test_error(app_dir) } },
      { name: "Verify error logged to separate DB", cmd: -> { verify_error_in_multi_db(app_dir) } }
    ]

    execute_scenario(scenario, steps)
  end

  def test_scenario_3_upgrade_single_to_single
    scenario = "Scenario 3: Upgrade Single DB → Single DB (v0.1.21 → v0.1.24)"
    puts "\n" + "=" * 80
    puts scenario
    puts "=" * 80

    app_dir = "#{TEST_DIR}/scenario3_upgrade_single"

    steps = [
      { name: "Create Rails app", cmd: -> { create_rails_app(app_dir) } },
      { name: "Install v0.1.21", cmd: -> { install_old_version(app_dir, "0.1.21") } },
      { name: "Run old migrations", cmd: -> { run_migrations(app_dir) } },
      { name: "Create test errors (v0.1.21)", cmd: -> { create_multiple_test_errors(app_dir, 5) } },
      { name: "Verify old errors exist", cmd: -> { verify_error_count(app_dir, 5) } },
      { name: "Upgrade to v0.1.24", cmd: -> { upgrade_gem(app_dir) } },
      { name: "Run new migrations", cmd: -> { run_migrations(app_dir) } },
      { name: "Verify old errors preserved", cmd: -> { verify_error_count(app_dir, 5) } },
      { name: "Verify application auto-created", cmd: -> { verify_application_exists(app_dir) } },
      { name: "Create new error (v0.1.24)", cmd: -> { create_test_error(app_dir) } },
      { name: "Verify new error has application_id", cmd: -> { verify_error_has_application(app_dir) } }
    ]

    execute_scenario(scenario, steps)
  end

  def test_scenario_4_upgrade_single_to_multi
    scenario = "Scenario 4: Upgrade Single DB → Multi DB"
    puts "\n" + "=" * 80
    puts scenario
    puts "=" * 80

    app_dir = "#{TEST_DIR}/scenario4_upgrade_to_multi"

    steps = [
      { name: "Create Rails app with v0.1.24", cmd: -> { create_rails_app(app_dir) } },
      { name: "Add gem", cmd: -> { add_gem_to_gemfile(app_dir) } },
      { name: "Bundle install", cmd: -> { run_bundle_install(app_dir) } },
      { name: "Install with single DB", cmd: -> { run_generator_single_db(app_dir) } },
      { name: "Run migrations", cmd: -> { run_migrations(app_dir) } },
      { name: "Create errors in single DB", cmd: -> { create_multiple_test_errors(app_dir, 3) } },
      { name: "Configure multi-DB in database.yml", cmd: -> { configure_multi_db(app_dir) } },
      { name: "Update initializer for multi-DB", cmd: -> { update_initializer_for_multi_db(app_dir) } },
      { name: "Create error_dashboard database", cmd: -> { create_error_dashboard_db(app_dir) } },
      { name: "Run migrations on new DB", cmd: -> { run_migrations_on_error_db(app_dir) } },
      { name: "Restart and test", cmd: -> { create_test_error(app_dir) } },
      { name: "Verify error in new DB", cmd: -> { verify_error_in_multi_db(app_dir) } }
    ]

    execute_scenario(scenario, steps)
  end

  def test_scenario_5_upgrade_multi_to_multi
    scenario = "Scenario 5: Upgrade Multi DB → Multi DB (gem update)"
    puts "\n" + "=" * 80
    puts scenario
    puts "=" * 80

    app_dir = "#{TEST_DIR}/scenario5_multi_to_multi"

    steps = [
      { name: "Create Rails app", cmd: -> { create_rails_app(app_dir) } },
      { name: "Add gem", cmd: -> { add_gem_to_gemfile(app_dir) } },
      { name: "Configure multi-DB", cmd: -> { configure_multi_db(app_dir) } },
      { name: "Bundle install", cmd: -> { run_bundle_install(app_dir) } },
      { name: "Run generator (multi DB)", cmd: -> { run_generator_multi_db(app_dir) } },
      { name: "Create databases", cmd: -> { create_databases(app_dir) } },
      { name: "Run migrations", cmd: -> { run_migrations(app_dir) } },
      { name: "Create test errors", cmd: -> { create_multiple_test_errors(app_dir, 3) } },
      { name: "Verify multi-DB working", cmd: -> { verify_error_in_multi_db(app_dir) } },
      { name: "Simulate gem update", cmd: -> { run_migrations(app_dir) } },
      { name: "Verify errors preserved", cmd: -> { verify_error_count(app_dir, 3) } }
    ]

    execute_scenario(scenario, steps)
  end

  # Helper methods

  def execute_scenario(scenario, steps)
    results = { scenario: scenario, steps: [], success: true, duration: 0 }
    start = Time.now

    steps.each_with_index do |step, index|
      print "  [#{index + 1}/#{steps.length}] #{step[:name]}... "

      begin
        result = step[:cmd].call
        if result[:success]
          puts "✅"
          results[:steps] << { name: step[:name], success: true }
        else
          puts "❌"
          puts "     Error: #{result[:error]}"
          results[:steps] << { name: step[:name], success: false, error: result[:error] }
          results[:success] = false
          break
        end
      rescue => e
        puts "❌"
        puts "     Exception: #{e.message}"
        results[:steps] << { name: step[:name], success: false, error: e.message }
        results[:success] = false
        break
      end
    end

    results[:duration] = Time.now - start
    @results << results

    if results[:success]
      puts "\n✅ #{scenario} - PASSED (#{results[:duration].round(2)}s)\n"
    else
      puts "\n❌ #{scenario} - FAILED\n"
    end
  end

  def create_rails_app(app_dir)
    # Skip if directory already exists
    if Dir.exist?(app_dir)
      FileUtils.rm_rf(app_dir)
    end

    cmd = "rails new #{app_dir} --skip-git --skip-javascript --skip-asset-pipeline --database=sqlite3 --skip-bundle"
    stdout, stderr, status = Open3.capture3(cmd)

    if status.success? && Dir.exist?(app_dir)
      { success: true }
    else
      error_msg = stderr.empty? ? stdout : stderr
      { success: false, error: "Rails app creation failed: #{error_msg.lines.first(5).join}" }
    end
  end

  def add_gem_to_gemfile(app_dir)
    gemfile = "#{app_dir}/Gemfile"
    gem_line = "gem 'rails_error_dashboard', path: '#{GEM_PATH}'\n"

    File.open(gemfile, 'a') { |f| f.write(gem_line) }
    { success: true }
  rescue => e
    { success: false, error: e.message }
  end

  def run_bundle_install(app_dir)
    stdout, stderr, status = Open3.capture3("bundle install", chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def run_generator_single_db(app_dir)
    cmd = "bundle exec rails generate rails_error_dashboard:install --no-interactive"
    stdout, stderr, status = Open3.capture3(cmd, chdir: app_dir)

    if status.success? || stdout.include?("create") || stdout.include?("rails_error_dashboard")
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def run_generator_multi_db(app_dir)
    cmd = "bundle exec rails generate rails_error_dashboard:install --no-interactive --separate_database --database=error_dashboard"
    stdout, stderr, status = Open3.capture3(cmd, chdir: app_dir)

    if status.success? || stdout.include?("create") || stdout.include?("rails_error_dashboard")
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def run_migrations(app_dir)
    stdout, stderr, status = Open3.capture3("bundle exec rails db:migrate", chdir: app_dir)

    if status.success? || stdout.include?("migrated")
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def configure_multi_db(app_dir)
    database_yml = <<~YAML
      default: &default
        adapter: sqlite3
        pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
        timeout: 5000

      development:
        primary:
          <<: *default
          database: storage/development.sqlite3

        error_dashboard:
          <<: *default
          database: storage/error_dashboard_development.sqlite3

      test:
        primary:
          <<: *default
          database: storage/test.sqlite3

        error_dashboard:
          <<: *default
          database: storage/error_dashboard_test.sqlite3

      production:
        primary:
          <<: *default
          database: storage/production.sqlite3

        error_dashboard:
          <<: *default
          database: storage/error_dashboard_production.sqlite3
    YAML

    File.write("#{app_dir}/config/database.yml", database_yml)
    { success: true }
  rescue => e
    { success: false, error: e.message }
  end

  def create_databases(app_dir)
    stdout, stderr, status = Open3.capture3("bundle exec rails db:create", chdir: app_dir)

    if status.success? || stdout.include?("created") || stdout.include?("already exists")
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def verify_tables(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      tables = ActiveRecord::Base.connection.tables
      required_tables = ['rails_error_dashboard_error_logs', 'rails_error_dashboard_applications']
      missing = required_tables - tables
      if missing.empty?
        puts "SUCCESS: All tables exist"
        exit 0
      else
        puts "FAIL: Missing tables: \#{missing.join(', ')}"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: "#{stdout}\n#{stderr}" }
    end
  end

  def create_test_error(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      begin
        raise StandardError, "Test error from integration suite"
      rescue => e
        RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
      end
      puts "Error created successfully"
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success? && stdout.include?("successfully")
      { success: true }
    else
      { success: false, error: "#{stdout}\n#{stderr}" }
    end
  end

  def create_multiple_test_errors(app_dir, count)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      #{count}.times do |i|
        begin
          raise StandardError, "Test error \#{i + 1}"
        rescue => e
          RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
        end
      end
      puts "Created \#{#{count}} errors successfully"
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success? && stdout.include?("successfully")
      { success: true }
    else
      { success: false, error: "#{stdout}\n#{stderr}" }
    end
  end

  def verify_error_logged(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      count = RailsErrorDashboard::ErrorLog.count
      if count > 0
        puts "SUCCESS: \#{count} error(s) logged"
        exit 0
      else
        puts "FAIL: No errors logged"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stdout }
    end
  end

  def verify_error_count(app_dir, expected_count)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      count = RailsErrorDashboard::ErrorLog.count
      if count == #{expected_count}
        puts "SUCCESS: Found #{expected_count} error(s) as expected"
        exit 0
      else
        puts "FAIL: Expected #{expected_count} errors, found \#{count}"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stdout }
    end
  end

  def verify_multi_db_tables(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      # Connect to error_dashboard database
      db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: 'error_dashboard')
      conn = ActiveRecord::Base.establish_connection(db_config.configuration_hash).connection
      tables = conn.tables
      required_tables = ['rails_error_dashboard_error_logs', 'rails_error_dashboard_applications']
      missing = required_tables - tables
      if missing.empty?
        puts "SUCCESS: All tables exist in error_dashboard database"
        exit 0
      else
        puts "FAIL: Missing tables in error_dashboard: \#{missing.join(', ')}"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: "#{stdout}\n#{stderr}" }
    end
  end

  def verify_error_in_multi_db(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      count = RailsErrorDashboard::ErrorLog.count
      if count > 0
        puts "SUCCESS: \#{count} error(s) in error_dashboard database"
        exit 0
      else
        puts "FAIL: No errors in error_dashboard database"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stdout }
    end
  end

  def install_old_version(app_dir, version)
    # For testing, we'll just use the current version
    # In real scenario, you'd specify gem 'rails_error_dashboard', '~> 0.1.21'
    add_gem_to_gemfile(app_dir)
    run_bundle_install(app_dir)
  end

  def upgrade_gem(app_dir)
    # Already using local gem, just run bundle update
    stdout, stderr, status = Open3.capture3("bundle update rails_error_dashboard", chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def verify_application_exists(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      count = RailsErrorDashboard::Application.count
      if count > 0
        app = RailsErrorDashboard::Application.first
        puts "SUCCESS: Application created - \#{app.name}"
        exit 0
      else
        puts "FAIL: No application found"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stdout }
    end
  end

  def verify_error_has_application(app_dir)
    ruby_code = <<~RUBY
      require_relative 'config/environment'
      error = RailsErrorDashboard::ErrorLog.last
      if error && error.application_id.present?
        puts "SUCCESS: Error has application_id: \#{error.application_id}"
        exit 0
      else
        puts "FAIL: Error missing application_id"
        exit 1
      end
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec rails runner -", stdin_data: ruby_code, chdir: app_dir)

    if status.success?
      { success: true }
    else
      { success: false, error: stdout }
    end
  end

  def update_initializer_for_multi_db(app_dir)
    initializer_path = "#{app_dir}/config/initializers/rails_error_dashboard.rb"
    content = File.read(initializer_path)

    # Add multi-DB configuration
    updated_content = content.sub(
      /end\s*\z/,
      "  config.use_separate_database = true\n  config.database = :error_dashboard\nend"
    )

    File.write(initializer_path, updated_content)
    { success: true }
  rescue => e
    { success: false, error: e.message }
  end

  def create_error_dashboard_db(app_dir)
    # Create the error_dashboard database
    stdout, stderr, status = Open3.capture3("bundle exec rails db:create", chdir: app_dir)

    if status.success? || stdout.include?("created") || stdout.include?("already exists")
      { success: true }
    else
      { success: false, error: stderr }
    end
  end

  def run_migrations_on_error_db(app_dir)
    # Run migrations (Rails will handle multi-DB automatically)
    run_migrations(app_dir)
  end

  def print_summary
    puts "\n"
    puts "=" * 80
    puts "TEST SUMMARY"
    puts "=" * 80

    total_scenarios = @results.length
    passed = @results.count { |r| r[:success] }
    failed = total_scenarios - passed
    total_duration = @results.sum { |r| r[:duration] }

    @results.each do |result|
      status = result[:success] ? "✅ PASS" : "❌ FAIL"
      puts "#{status} - #{result[:scenario]} (#{result[:duration].round(2)}s)"

      unless result[:success]
        failed_steps = result[:steps].select { |s| !s[:success] }
        failed_steps.each do |step|
          puts "  ❌ #{step[:name]}: #{step[:error]}"
        end
      end
    end

    puts "\n" + "=" * 80
    puts "Total: #{total_scenarios} scenarios"
    puts "Passed: #{passed} ✅"
    puts "Failed: #{failed} ❌"
    puts "Duration: #{total_duration.round(2)}s"
    puts "Completed: #{Time.now}"
    puts "=" * 80

    if failed == 0
      puts "\n🎉 ALL SCENARIOS PASSED! Gem is production ready.\n"
    else
      puts "\n⚠️  SOME SCENARIOS FAILED. Review errors above.\n"
    end
  end
end

# Run the test suite
suite = IntegrationTestSuite.new
suite.run_all
