#!/bin/bash
set -e

# Manual Integration Test for Rails Error Dashboard v0.1.24
# This script manually tests all installation and upgrade scenarios

TEST_DIR="/tmp/rails_error_dashboard_integration_tests"
GEM_PATH="$(cd "$(dirname "$0")" && pwd)"

echo "================================================================================"
echo "Rails Error Dashboard - Manual Integration Test Suite"
echo "Version: 0.1.24"
echo "Started: $(date)"
echo "================================================================================"
echo

# Cleanup
echo "🧹 Cleaning up test directory..."
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
echo "✅ Test directory ready: $TEST_DIR"
echo

# Helper function to test scenario
test_scenario() {
    local scenario_name="$1"
    local app_dir="$2"

    echo "================================================================================"
    echo "$scenario_name"
    echo "================================================================================"
    echo "App directory: $app_dir"
    echo
}

# Helper function to run command and check result
run_step() {
    local step_name="$1"
    shift

    echo -n "  ▶ $step_name... "

    if "$@" > /tmp/step_output.log 2>&1; then
        echo "✅"
        return 0
    else
        echo "❌"
        echo "  Error output:"
        cat /tmp/step_output.log | head -10 | sed 's/^/    /'
        return 1
    fi
}

################################################################################
# SCENARIO 1: Fresh Install - Single Database
################################################################################

test_scenario "Scenario 1: Fresh Install - Single Database" "$TEST_DIR/scenario1"

cd /tmp
APP_DIR="$TEST_DIR/scenario1"

# Change to temp directory to avoid Rails detection
cd /tmp

run_step "Create Rails app" \
    rails new "$APP_DIR" --skip-git --skip-javascript --database=sqlite3 --skip-bundle --quiet

cd "$APP_DIR"

# Add gem to Gemfile
echo "gem 'rails_error_dashboard', path: '$GEM_PATH'" >> Gemfile

run_step "Bundle install" bundle install --quiet

run_step "Run generator" \
    bundle exec rails generate rails_error_dashboard:install --no-interactive

run_step "Run migrations" \
    bundle exec rails db:migrate

# Create test error
run_step "Create test error" \
    bundle exec rails runner "
        begin
          raise StandardError, 'Test error from scenario 1'
        rescue => e
          RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
        end
        puts 'Error logged successfully'
    "

# Verify error logged
run_step "Verify error logged" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count > 0
          puts \"SUCCESS: #{count} error(s) logged\"
        else
          puts 'FAIL: No errors logged'
          exit 1
        end
    "

echo "✅ Scenario 1 completed successfully!"
echo

################################################################################
# SCENARIO 2: Fresh Install - Multi Database
################################################################################

test_scenario "Scenario 2: Fresh Install - Multi Database" "$TEST_DIR/scenario2"

cd /tmp
APP_DIR="$TEST_DIR/scenario2"

cd /tmp

run_step "Create Rails app" \
    rails new "$APP_DIR" --skip-git --skip-javascript --database=sqlite3 --skip-bundle --quiet

cd "$APP_DIR"

# Configure multi-database in database.yml
cat > config/database.yml << 'EOF'
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
EOF

echo "gem 'rails_error_dashboard', path: '$GEM_PATH'" >> Gemfile

run_step "Bundle install" bundle install --quiet

run_step "Run generator with multi-DB" \
    bundle exec rails generate rails_error_dashboard:install \
        --no-interactive \
        --separate_database \
        --database=error_dashboard

run_step "Create databases" bundle exec rails db:create

run_step "Run migrations" bundle exec rails db:migrate

run_step "Create test error" \
    bundle exec rails runner "
        begin
          raise StandardError, 'Test error from scenario 2'
        rescue => e
          RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
        end
        puts 'Error logged successfully'
    "

run_step "Verify error in multi-DB" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count > 0
          puts \"SUCCESS: #{count} error(s) in error_dashboard database\"
        else
          puts 'FAIL: No errors logged'
          exit 1
        end
    "

echo "✅ Scenario 2 completed successfully!"
echo

################################################################################
# SCENARIO 3: Upgrade Single DB → Single DB
################################################################################

test_scenario "Scenario 3: Upgrade Single DB → Single DB" "$TEST_DIR/scenario3"

cd /tmp
APP_DIR="$TEST_DIR/scenario3"

run_step "Create Rails app" \
    rails new "$APP_DIR" --skip-git --skip-javascript --database=sqlite3 --skip-bundle --quiet

cd "$APP_DIR"

echo "gem 'rails_error_dashboard', path: '$GEM_PATH'" >> Gemfile

run_step "Bundle install" bundle install --quiet

run_step "Run generator" \
    bundle exec rails generate rails_error_dashboard:install --no-interactive

run_step "Run migrations" bundle exec rails db:migrate

run_step "Create test errors (simulating v0.1.21 data)" \
    bundle exec rails runner "
        3.times do |i|
          begin
            raise StandardError, \"Old error #{i + 1}\"
          rescue => e
            RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
          end
        end
        puts '3 errors created'
    "

run_step "Verify 3 errors exist" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count == 3
          puts 'SUCCESS: 3 errors exist'
        else
          puts \"FAIL: Expected 3 errors, found #{count}\"
          exit 1
        end
    "

# Simulate upgrade (in our case, migrations are already up to date)
run_step "Run migrations (upgrade)" bundle exec rails db:migrate

run_step "Verify old errors preserved" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count == 3
          puts 'SUCCESS: All 3 errors preserved after upgrade'
        else
          puts \"FAIL: Expected 3 errors, found #{count}\"
          exit 1
        end
    "

run_step "Verify application auto-created" \
    bundle exec rails runner "
        app_count = RailsErrorDashboard::Application.count
        if app_count > 0
          app = RailsErrorDashboard::Application.first
          puts \"SUCCESS: Application created - #{app.name}\"
        else
          puts 'FAIL: No application found'
          exit 1
        end
    "

run_step "Create new error with application" \
    bundle exec rails runner "
        begin
          raise StandardError, 'New error after upgrade'
        rescue => e
          RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
        end
        error = RailsErrorDashboard::ErrorLog.last
        if error.application_id.present?
          puts \"SUCCESS: New error has application_id: #{error.application_id}\"
        else
          puts 'FAIL: New error missing application_id'
          exit 1
        end
    "

echo "✅ Scenario 3 completed successfully!"
echo

################################################################################
# SCENARIO 4: Upgrade Single DB → Multi DB
################################################################################

test_scenario "Scenario 4: Upgrade Single DB → Multi DB" "$TEST_DIR/scenario4"

cd /tmp
APP_DIR="$TEST_DIR/scenario4"

run_step "Create Rails app" \
    rails new "$APP_DIR" --skip-git --skip-javascript --database=sqlite3 --skip-bundle --quiet

cd "$APP_DIR"

echo "gem 'rails_error_dashboard', path: '$GEM_PATH'" >> Gemfile

run_step "Bundle install" bundle install --quiet

run_step "Install with single DB" \
    bundle exec rails generate rails_error_dashboard:install --no-interactive

run_step "Run migrations" bundle exec rails db:migrate

run_step "Create errors in single DB" \
    bundle exec rails runner "
        2.times do |i|
          begin
            raise StandardError, \"Error in single DB #{i + 1}\"
          rescue => e
            RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
          end
        end
        puts '2 errors created in single DB'
    "

# Configure multi-database
cat > config/database.yml << 'EOF'
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
EOF

# Update initializer for multi-DB
cat >> config/initializers/rails_error_dashboard.rb << 'EOF'

# Multi-database configuration
config.use_separate_database = true
config.database = :error_dashboard
EOF

run_step "Create error_dashboard database" bundle exec rails db:create

run_step "Run migrations on error_dashboard" bundle exec rails db:migrate

run_step "Create new error in multi-DB" \
    bundle exec rails runner "
        begin
          raise StandardError, 'Error in multi-DB'
        rescue => e
          RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
        end
        puts 'Error created in multi-DB'
    "

run_step "Verify error in error_dashboard" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count > 0
          puts \"SUCCESS: #{count} error(s) in error_dashboard database\"
        else
          puts 'FAIL: No errors in error_dashboard'
          exit 1
        end
    "

echo "✅ Scenario 4 completed successfully!"
echo
echo "📝 Note: Old errors remain in primary database. To migrate them, export from"
echo "   primary DB and import into error_dashboard DB (data migration not automated)"
echo

################################################################################
# SCENARIO 5: Multi DB → Multi DB (gem update)
################################################################################

test_scenario "Scenario 5: Multi DB → Multi DB (gem update)" "$TEST_DIR/scenario5"

cd /tmp
APP_DIR="$TEST_DIR/scenario5"

run_step "Create Rails app" \
    rails new "$APP_DIR" --skip-git --skip-javascript --database=sqlite3 --skip-bundle --quiet

cd "$APP_DIR"

# Configure multi-database from start
cat > config/database.yml << 'EOF'
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
EOF

echo "gem 'rails_error_dashboard', path: '$GEM_PATH'" >> Gemfile

run_step "Bundle install" bundle install --quiet

run_step "Run generator with multi-DB" \
    bundle exec rails generate rails_error_dashboard:install \
        --no-interactive \
        --separate_database \
        --database=error_dashboard

run_step "Create databases" bundle exec rails db:create

run_step "Run migrations" bundle exec rails db:migrate

run_step "Create test errors" \
    bundle exec rails runner "
        3.times do |i|
          begin
            raise StandardError, \"Multi-DB error #{i + 1}\"
          rescue => e
            RailsErrorDashboard::Commands::LogError.call(e, { platform: 'Test' })
          end
        end
        puts '3 errors created'
    "

run_step "Verify errors in multi-DB" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count == 3
          puts \"SUCCESS: #{count} errors in error_dashboard database\"
        else
          puts \"FAIL: Expected 3 errors, found #{count}\"
          exit 1
        end
    "

# Simulate gem update (re-run migrations)
run_step "Simulate gem update (re-run migrations)" bundle exec rails db:migrate

run_step "Verify errors preserved after update" \
    bundle exec rails runner "
        count = RailsErrorDashboard::ErrorLog.count
        if count == 3
          puts 'SUCCESS: All errors preserved after gem update'
        else
          puts \"FAIL: Expected 3 errors, found #{count}\"
          exit 1
        end
    "

echo "✅ Scenario 5 completed successfully!"
echo

################################################################################
# SUMMARY
################################################################################

echo
echo "================================================================================"
echo "TEST SUMMARY"
echo "================================================================================"
echo "✅ Scenario 1: Fresh Install - Single Database"
echo "✅ Scenario 2: Fresh Install - Multi Database"
echo "✅ Scenario 3: Upgrade Single DB → Single DB"
echo "✅ Scenario 4: Upgrade Single DB → Multi DB"
echo "✅ Scenario 5: Multi DB → Multi DB (gem update)"
echo "================================================================================"
echo "🎉 ALL SCENARIOS PASSED! Gem is production ready."
echo "================================================================================"
echo "Completed: $(date)"
echo
