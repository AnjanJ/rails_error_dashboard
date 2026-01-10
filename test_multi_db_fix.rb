#!/usr/bin/env ruby
# Quick test to verify multi-database fix works

require 'fileutils'
require 'open3'

GEM_PATH = File.expand_path('..', __FILE__)
TEMP_DIR = "/tmp/test_multidb_v0124"

puts "\n" + "=" * 60
puts "Testing Multi-Database Fix for v0.1.24"
puts "=" * 60 + "\n"

FileUtils.rm_rf(TEMP_DIR)
FileUtils.mkdir_p(TEMP_DIR)

def run_command(cmd, dir = nil)
  original_dir = Dir.pwd
  Dir.chdir(dir) if dir
  stdout, stderr, status = Open3.capture3(cmd)
  Dir.chdir(original_dir)
  { stdout: stdout, stderr: stderr, success: status.success? }
end

# Test Scenario 2: Fresh Install with Multi-Database
puts "\n🧪 Testing Scenario 2: Fresh Install - Multi Database\n"
puts "-" * 60

app_dir = File.join(TEMP_DIR, "test_multi_db")

# Create Rails app
puts "Creating Rails app..."
result = run_command("rails new test_multi_db --skip-git --skip-test --skip-bundle --database=sqlite3 -q", TEMP_DIR)

unless result[:success]
  puts "❌ Failed to create Rails app"
  exit 1
end

# Add gem
puts "Adding gem to Gemfile..."
File.open(File.join(app_dir, "Gemfile"), "a") do |f|
  f.puts "gem 'rails_error_dashboard', path: '#{GEM_PATH}'"
end

# Bundle install
puts "Running bundle install..."
result = run_command("bundle install --quiet", app_dir)

# Configure multi-database in database.yml
puts "Configuring multi-database..."
File.open(File.join(app_dir, "config", "database.yml"), "a") do |f|
  f.puts "\n  error_dashboard:"
  f.puts "    <<: *default"
  f.puts "    database: db/error_dashboard_development.sqlite3"
end

# Run generator with database flag
puts "Running generator with --database flag..."
result = run_command(
  "bundle exec rails generate rails_error_dashboard:install --no-interactive --separate_database --database=error_dashboard --quiet",
  app_dir
)

# Check if config was set correctly
initializer_path = File.join(app_dir, "config", "initializers", "rails_error_dashboard.rb")
initializer_content = File.read(initializer_path)

if initializer_content.include?("config.database = :error_dashboard")
  puts "✅ Generator set config.database correctly"
else
  puts "❌ Generator did not set config.database"
  puts "Initializer content:"
  puts initializer_content[/DATABASE CONFIGURATION.*?ADVANCED ANALYTICS/m]
  exit 1
end

# Run migrations
puts "Running migrations..."
result = run_command("bundle exec rails db:migrate 2>&1", app_dir)

unless result[:success]
  puts "❌ Migrations failed:"
  puts result[:stdout]
  puts result[:stderr]
  exit 1
end

puts "✅ Migrations completed successfully"

# Test error creation
puts "Testing error creation..."
test_script = <<-RUBY
  begin
    raise StandardError, 'Test error for multi-database verification'
  rescue => e
    result = RailsErrorDashboard::Commands::LogError.call(
      exception: e,
      platform: 'Web'
    )

    if result.success?
      puts "Apps: \#{RailsErrorDashboard::Application.count}"
      puts "Errors: \#{RailsErrorDashboard::ErrorLog.count}"

      if RailsErrorDashboard::ErrorLog.any?
        error = RailsErrorDashboard::ErrorLog.first
        puts "Error type: \#{error.error_type}"
        puts "Has application: \#{error.application.present?}"
        puts "Application name: \#{error.application.name}"
      end
    else
      puts "ERROR: Failed to log error"
      puts result.error
      exit 1
    end
  end
RUBY

File.write(File.join(app_dir, "test_error.rb"), test_script)
result = run_command("bundle exec rails runner test_error.rb", app_dir)

if result[:success] && result[:stdout].include?("Test error for multi-database")
  puts "✅ Error creation successful"
  puts result[:stdout]
else
  puts "❌ Error creation failed:"
  puts result[:stdout]
  puts result[:stderr]
  exit 1
end

puts "\n" + "=" * 60
puts "✅ Multi-Database Fix VERIFIED!"
puts "=" * 60
puts "\nScenario 2 now PASSES - Multi-database support is working!\n"

# Cleanup
puts "\nCleaning up test files..."
FileUtils.rm_rf(TEMP_DIR)

puts "\n✅ All tests passed!\n"
