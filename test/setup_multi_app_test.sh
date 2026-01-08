#!/bin/bash

# Multi-App Test Setup Script
# Creates multiple test apps that share the error dashboard database

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Rails Error Dashboard - Multi-App Test Setup                ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo ""

# Configuration
TEST_DIR="$HOME/code/test"
GEM_PATH="/Users/aj/code/rails_error_dashboard"

# Test apps to create
APPS=(
  "blog_app:BlogApp"
  "api_service:ApiService"
  "admin_panel:AdminPanel"
  "mobile_backend:MobileBackend"
)

echo -e "${YELLOW}→ Configuration:${NC}"
echo -e "  Test directory: $TEST_DIR"
echo -e "  Gem path: $GEM_PATH"
echo -e "  Apps to create: ${#APPS[@]}"
echo ""

# Create test directory
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo -e "${GREEN}✓${NC} Test directory ready"
echo ""

# Function to create a test app
create_test_app() {
  local app_dir=$1
  local app_name=$2

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Creating app: ${app_name} (${app_dir})${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Skip if already exists
  if [ -d "$app_dir" ]; then
    echo -e "${YELLOW}⚠${NC}  App already exists, skipping creation..."
    return 0
  fi

  # Create Rails app
  echo -e "${YELLOW}→${NC} Creating Rails app..."
  rails new "$app_dir" --skip-git --skip-test --skip-bundle -d sqlite3 -q

  cd "$app_dir"

  # Add error dashboard gem from local path
  echo -e "${YELLOW}→${NC} Adding rails_error_dashboard gem..."
  cat >> Gemfile <<RUBY

# Rails Error Dashboard (local development)
gem 'rails_error_dashboard', path: '$GEM_PATH'
RUBY

  # Bundle install
  echo -e "${YELLOW}→${NC} Running bundle install..."
  bundle install --quiet

  # Create initializer
  echo -e "${YELLOW}→${NC} Creating initializer..."
  mkdir -p config/initializers
  cat > config/initializers/rails_error_dashboard.rb <<RUBY
RailsErrorDashboard.configure do |config|
  # Set application name
  config.application_name = "$app_name"

  # Use shared database
  config.database = :error_dashboard

  # Note: Authentication is always required and cannot be disabled
  # Use default credentials: gandalf / youshallnotpass
end
RUBY

  # Configure database to use shared error dashboard DB
  echo -e "${YELLOW}→${NC} Configuring shared database..."
  cat > config/database.yml <<YAML
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  <<: *default
  database: storage/development.sqlite3

  # Shared error dashboard database
  error_dashboard:
    <<: *default
    database: $TEST_DIR/shared_error_dashboard.sqlite3

test:
  <<: *default
  database: storage/test.sqlite3

production:
  <<: *default
  database: storage/production.sqlite3
YAML

  # Mount the engine
  echo -e "${YELLOW}→${NC} Mounting error dashboard engine..."
  cat > config/routes.rb <<RUBY
Rails.application.routes.draw do
  mount RailsErrorDashboard::Engine => "/error_dashboard"

  # Test routes
  get '/trigger_error/:type', to: 'errors_test#trigger'
  get '/health', to: 'errors_test#health'
end
RUBY

  # Create test controller for triggering errors
  echo -e "${YELLOW}→${NC} Creating test controller..."
  mkdir -p app/controllers
  cat > app/controllers/errors_test_controller.rb <<RUBY
class ErrorsTestController < ApplicationController
  def health
    render json: {
      status: 'ok',
      app: '$app_name',
      time: Time.current
    }
  end

  def trigger
    error_type = params[:type] || 'standard'

    case error_type
    when 'standard'
      raise StandardError, "Test error from $app_name at #{Time.current}"
    when 'argument'
      raise ArgumentError, "Invalid argument in $app_name"
    when 'runtime'
      raise RuntimeError, "Runtime error in $app_name processing"
    when 'notfound'
      raise ActiveRecord::RecordNotFound, "Record not found in $app_name"
    when 'validation'
      raise ActiveRecord::RecordInvalid, "Validation failed in $app_name"
    when 'timeout'
      raise Timeout::Error, "Request timeout in $app_name"
    when 'zerodiv'
      result = 10 / 0
    when 'nil'
      nil.foo
    when 'type'
      "string" + 5
    when 'name'
      undefined_variable
    else
      raise "Unknown error type: #{error_type} in $app_name"
    end

    render json: { status: 'ok' }
  rescue => e
    # Log the error
    RailsErrorDashboard::Commands::LogError.call(e, {
      request_url: request.url,
      user_agent: request.user_agent,
      ip_address: request.remote_ip,
      platform: ['iOS', 'Android', 'Web', 'API'].sample
    })

    render json: {
      error: e.class.name,
      message: e.message,
      app: '$app_name'
    }, status: 500
  end
end
RUBY

  # Run migrations
  echo -e "${YELLOW}→${NC} Running migrations..."
  rails db:create db:migrate >/dev/null 2>&1 || true

  echo -e "${GREEN}✓${NC} App ${app_name} created successfully"
  echo ""

  cd "$TEST_DIR"
}

# Create all test apps
for app_config in "${APPS[@]}"; do
  IFS=':' read -r app_dir app_name <<< "$app_config"
  create_test_app "$app_dir" "$app_name"
done

# Initialize shared database
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Initializing shared error dashboard database${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Use first app to run migrations on shared DB
cd "${APPS[0]%%:*}"
echo -e "${YELLOW}→${NC} Running error dashboard migrations on shared DB..."

# Copy migrations from gem to app
rails rails_error_dashboard:install:migrations >/dev/null 2>&1 || true

# Run migrations on error_dashboard database
RAILS_ENV=development DATABASE=error_dashboard rails db:migrate >/dev/null 2>&1 || true

echo -e "${GREEN}✓${NC} Shared database initialized"
echo ""

cd "$TEST_DIR"

# Create error generation script
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Creating error generation script${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cat > "$TEST_DIR/generate_errors.sh" <<'SCRIPT'
#!/bin/bash

# Generate test errors across all apps
set -e

echo "🔥 Generating test errors across all apps..."
echo ""

APPS=(
  "blog_app:BlogApp:3001"
  "api_service:ApiService:3002"
  "admin_panel:AdminPanel:3003"
  "mobile_backend:MobileBackend:3004"
)

ERROR_TYPES=(
  "standard"
  "argument"
  "runtime"
  "notfound"
  "validation"
  "timeout"
  "zerodiv"
  "nil"
  "type"
  "name"
)

ERRORS_PER_APP=75

for app_config in "${APPS[@]}"; do
  IFS=':' read -r app_dir app_name port <<< "$app_config"

  echo "📱 Generating errors for $app_name (port $port)..."

  # Check if server is running
  if ! curl -s "http://localhost:$port/health" >/dev/null 2>&1; then
    echo "   ⚠️  Server not running on port $port - skipping"
    continue
  fi

  count=0
  for i in $(seq 1 $ERRORS_PER_APP); do
    error_type=${ERROR_TYPES[$RANDOM % ${#ERROR_TYPES[@]}]}

    # Trigger error
    curl -s "http://localhost:$port/trigger_error/$error_type" >/dev/null 2>&1 || true

    count=$((count + 1))

    # Progress indicator
    if [ $((count % 10)) -eq 0 ]; then
      echo -n "."
    fi

    # Small delay to avoid overwhelming the server
    sleep 0.05
  done

  echo ""
  echo "   ✓ Generated $count errors for $app_name"
  echo ""
done

echo "✅ Error generation complete!"
echo ""
echo "Visit http://localhost:3001/error_dashboard to view the dashboard"
SCRIPT

chmod +x "$TEST_DIR/generate_errors.sh"

echo -e "${GREEN}✓${NC} Error generation script created"
echo ""

# Create server start script
cat > "$TEST_DIR/start_servers.sh" <<'SCRIPT'
#!/bin/bash

# Start all test app servers

TEST_DIR="$HOME/code/test"
cd "$TEST_DIR"

echo "🚀 Starting all test app servers..."
echo ""

# Kill any existing servers
pkill -f "rails s" || true
sleep 2

APPS=(
  "blog_app:BlogApp:3001"
  "api_service:ApiService:3002"
  "admin_panel:AdminPanel:3003"
  "mobile_backend:MobileBackend:3004"
)

for app_config in "${APPS[@]}"; do
  IFS=':' read -r app_dir app_name port <<< "$app_config"

  cd "$TEST_DIR/$app_dir"

  echo "→ Starting $app_name on port $port..."
  rails s -p $port -d -P "tmp/pids/server-$port.pid" >/dev/null 2>&1

  # Wait for server to start
  sleep 3

  # Check if started
  if curl -s "http://localhost:$port/health" >/dev/null 2>&1; then
    echo "  ✓ $app_name running on http://localhost:$port"
  else
    echo "  ✗ $app_name failed to start"
  fi
done

echo ""
echo "✅ All servers started!"
echo ""
echo "Access points:"
echo "  BlogApp:        http://localhost:3001/error_dashboard"
echo "  ApiService:     http://localhost:3002/error_dashboard"
echo "  AdminPanel:     http://localhost:3003/error_dashboard"
echo "  MobileBackend:  http://localhost:3004/error_dashboard"
echo ""
echo "Generate errors: ./generate_errors.sh"
echo "Stop servers:    ./stop_servers.sh"
SCRIPT

chmod +x "$TEST_DIR/start_servers.sh"

# Create server stop script
cat > "$TEST_DIR/stop_servers.sh" <<'SCRIPT'
#!/bin/bash

echo "🛑 Stopping all test app servers..."
pkill -f "rails s" || true
echo "✓ All servers stopped"
SCRIPT

chmod +x "$TEST_DIR/stop_servers.sh"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    SETUP COMPLETE! 🎉                         ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo ""
echo -e "${GREEN}✓${NC} Created ${#APPS[@]} test applications"
echo -e "${GREEN}✓${NC} Configured shared error dashboard database"
echo -e "${GREEN}✓${NC} Generated helper scripts"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Start all servers:     ${BLUE}cd $TEST_DIR && ./start_servers.sh${NC}"
echo -e "  2. Generate test errors:  ${BLUE}./generate_errors.sh${NC}"
echo -e "  3. View dashboard:        ${BLUE}http://localhost:3001/error_dashboard${NC}"
echo -e "  4. Stop servers:          ${BLUE}./stop_servers.sh${NC}"
echo ""
echo -e "${YELLOW}Test Applications:${NC}"
for app_config in "${APPS[@]}"; do
  IFS=':' read -r app_dir app_name port <<< "$app_config"
  echo -e "  • $app_name ($app_dir) - Port $((3000 + ${#app_dir}))"
done
echo ""
echo -e "${YELLOW}Helper Scripts Created:${NC}"
echo -e "  • start_servers.sh  - Start all Rails servers"
echo -e "  • stop_servers.sh   - Stop all Rails servers"
echo -e "  • generate_errors.sh - Generate 75 errors per app"
echo ""
