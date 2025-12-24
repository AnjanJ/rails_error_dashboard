# Rails Error Dashboard

[![Gem Version](https://badge.fury.io/rb/rails_error_dashboard.svg)](https://badge.fury.io/rb/rails_error_dashboard)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **A beautiful, production-ready error tracking dashboard for Rails applications**

Rails Error Dashboard provides a complete error tracking solution with a modern UI, real-time analytics, platform detection (iOS/Android/API), and optional separate database support. Built with Rails 7+ error reporting and following Service Objects + CQRS principles.

![Dashboard Screenshot](https://via.placeholder.com/800x400?text=Error+Dashboard+Screenshot)

## ✨ Features

### 🎯 Complete Error Tracking
- **Automatic error capture** from controllers, jobs, services, and middleware
- **Platform detection** (iOS/Android/API) using user agent parsing
- **User context tracking** with optional user associations
- **Request context** including URL, params, IP address
- **Full stack traces** for debugging

### 📊 Beautiful Dashboard
- **Modern UI** with Bootstrap 5
- **Dark/Light mode** with theme switcher
- **Responsive design** for mobile and desktop
- **Real-time statistics** and error counts
- **Search and filtering** by type, platform, environment
- **Fast pagination** with Pagy (40x faster than Kaminari)

### 📈 Analytics & Insights
- **Time-series charts** showing error trends
- **Breakdown by type**, platform, and environment
- **Resolution rate tracking**
- **Top affected users**
- **Mobile vs API analysis**
- **Customizable date ranges** (7, 14, 30, 90 days)

### ✅ Resolution Tracking
- Mark errors as resolved
- Add resolution comments
- Link to PRs, commits, or issues
- Track resolver name and timestamp
- View related errors

### 🔒 Security & Configuration
- **HTTP Basic Auth** (configurable)
- **Environment-based settings**
- **Optional Slack notifications**
- **Optional separate database** for performance isolation

### 🏗️ Architecture
Built with **Service Objects + CQRS Principles**:
- **Commands**: LogError, ResolveError (write operations)
- **Queries**: ErrorsList, DashboardStats, AnalyticsStats (read operations)
- **Value Objects**: ErrorContext (immutable data)
- **Services**: PlatformDetector (business logic)

## 📦 Installation

### 1. Add to Gemfile

```ruby
gem 'rails_error_dashboard'
```

### 2. Install the gem

```bash
bundle install
```

### 3. Run the installer

```bash
rails generate rails_error_dashboard:install
```

This will:
- Create `config/initializers/rails_error_dashboard.rb`
- Copy migrations to your app
- Mount the engine at `/error_dashboard`

### 4. Run migrations

```bash
rails db:migrate
```

### 5. Visit the dashboard

Start your server and visit:
```
http://localhost:3000/error_dashboard
```

**Default credentials** (change in the initializer):
- Username: `admin`
- Password: `password`

## ⚙️ Configuration

Edit `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  # Dashboard authentication
  config.dashboard_username = ENV.fetch('ERROR_DASHBOARD_USER', 'admin')
  config.dashboard_password = ENV.fetch('ERROR_DASHBOARD_PASSWORD', 'password')
  config.require_authentication = true
  config.require_authentication_in_development = false

  # User model for associations
  config.user_model = 'User'

  # Slack notifications (optional)
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  # Separate database (optional - for high-volume apps)
  config.use_separate_database = ENV.fetch('USE_SEPARATE_ERROR_DB', 'false') == 'true'

  # Retention policy
  config.retention_days = 90

  # Error catching
  config.enable_middleware = true
  config.enable_error_subscriber = true
end
```

### Environment Variables

```bash
# .env
ERROR_DASHBOARD_USER=admin
ERROR_DASHBOARD_PASSWORD=your_secure_password
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
USE_SEPARATE_ERROR_DB=false  # Set to true for separate database
```

## 🚀 Usage

### Automatic Error Tracking

The gem automatically tracks errors from:
- **Controllers** (via Rails error reporting)
- **Background jobs** (ActiveJob, Sidekiq)
- **Rack middleware** (catches everything else)

No code changes needed! Just install and go.

### Manual Error Logging

You can also manually log errors:

```ruby
begin
  # Your code
rescue => e
  Rails.error.report(e,
    handled: true,
    severity: :error,
    context: {
      current_user: current_user,
      custom_data: "anything you want"
    }
  )
end
```

### Accessing the Dashboard

Navigate to `/error_dashboard` to view:
- **Overview**: Recent errors, statistics, quick filters
- **All Errors**: Paginated list with filtering and search
- **Analytics**: Charts, trends, and insights
- **Error Details**: Full stack trace, context, and resolution tracking

### Resolution Workflow

1. Click on an error to view details
2. Investigate the stack trace and context
3. Fix the issue in your code
4. Mark as resolved with:
   - Resolution comment (what was the fix)
   - Reference link (PR, commit, issue)
   - Your name

## 🗄️ Optional Separate Database

For high-volume applications, you can use a separate database for error logs:

### Benefits
- **Performance isolation** - error logging doesn't slow down main DB
- **Independent scaling** - different hardware for different workloads
- **Different retention policies** - auto-delete old errors
- **Security isolation** - separate access controls

### Setup

1. **Enable in config**:
```ruby
config.use_separate_database = true
```

2. **Configure database.yml**:
```yaml
production:
  primary:
    database: myapp_production
    # ... your main DB config

  error_logs:
    database: myapp_error_logs_production
    username: <%= ENV['ERROR_LOGS_DATABASE_USER'] %>
    password: <%= ENV['ERROR_LOGS_DATABASE_PASSWORD'] %>
    migrations_paths: db/error_logs_migrate
```

3. **Create and migrate**:
```bash
rails db:create:error_logs
rails db:migrate:error_logs
```

## 🔧 Advanced Features

### Slack Notifications

Set `SLACK_WEBHOOK_URL` in your environment to receive notifications for new errors.

### Platform Detection

Automatically detects:
- **iOS** - iPhone, iPad apps
- **Android** - Android apps
- **API** - Backend services, web requests

### User Association

Errors are automatically associated with the current user (if signed in). Configure the user model name if it's not `User`.

### Retention Policy

Old errors are automatically cleaned up based on `retention_days` configuration.

## 📊 Architecture Details

### Service Objects Pattern

**Commands** (Write Operations):
```ruby
# Create an error log
RailsErrorDashboard::Commands::LogError.call(exception, context)

# Mark error as resolved
RailsErrorDashboard::Commands::ResolveError.call(error_id, resolution_data)
```

**Queries** (Read Operations):
```ruby
# Get filtered errors
RailsErrorDashboard::Queries::ErrorsList.call(filters)

# Get dashboard stats
RailsErrorDashboard::Queries::DashboardStats.call

# Get analytics
RailsErrorDashboard::Queries::AnalyticsStats.call(days: 30)
```

### Database Schema

```ruby
create_table :rails_error_dashboard_error_logs do |t|
  # Error details
  t.string :error_type, null: false
  t.text :message, null: false
  t.text :backtrace

  # Context
  t.integer :user_id
  t.text :request_url
  t.text :request_params
  t.text :user_agent
  t.string :ip_address
  t.string :environment, null: false
  t.string :platform

  # Resolution tracking
  t.boolean :resolved, default: false
  t.text :resolution_comment
  t.string :resolution_reference
  t.string :resolved_by_name
  t.datetime :resolved_at

  # Timestamps
  t.datetime :occurred_at, null: false
  t.timestamps
end
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
git clone https://github.com/yourusername/rails_error_dashboard.git
cd rails_error_dashboard
bundle install
```

## 📝 License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🙏 Acknowledgments

- Built with [Rails](https://rubyonrails.org/)
- UI powered by [Bootstrap 5](https://getbootstrap.com/)
- Charts by [Chart.js](https://www.chartjs.org/)
- Pagination by [Pagy](https://github.com/ddnexus/pagy)
- Platform detection by [Browser](https://github.com/fnando/browser)

## 📮 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/rails_error_dashboard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/rails_error_dashboard/discussions)

---

**Made with ❤️ by Anjan for the Rails community**
