# Rails Error Dashboard

[![Gem Version](https://badge.fury.io/rb/rails_error_dashboard.svg)](https://badge.fury.io/rb/rails_error_dashboard)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **A beautiful, production-ready error tracking dashboard for Rails applications and their frontends**

Rails Error Dashboard provides a complete error tracking and alerting solution for Rails backends AND frontend/mobile apps (React, React Native, Vue, Angular, Flutter, etc.). Features include: modern UI, multi-channel notifications (Slack + Email), real-time analytics, platform detection (iOS/Android/Web/API), and optional separate database support. Built with Rails 7+ error reporting and following Service Objects + CQRS principles.

![Dashboard Screenshot](https://via.placeholder.com/800x400?text=Error+Dashboard+Screenshot)

## ✨ Features

### 🎯 Complete Error Tracking
- **Automatic error capture** from Rails controllers, jobs, services, and middleware
- **Frontend & mobile support** - React, React Native, Vue, Angular, Flutter, and more
- **Platform detection** (iOS/Android/Web/API) using user agent parsing
- **User context tracking** with optional user associations
- **Request context** including URL, params, IP address, component/screen
- **Full stack traces** for debugging (Ruby + JavaScript)

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

### 🚨 Multi-Channel Alerting
- **Slack notifications** with beautifully formatted messages
- **Email alerts** with HTML templates to multiple recipients
- **Instant notifications** when errors occur (async background jobs)
- **Rich context** including user, platform, environment, stack trace
- **Direct links** to view full error details in dashboard
- **Customizable** - enable/disable channels independently

### 🔒 Security & Configuration
- **HTTP Basic Auth** (configurable)
- **Environment-based settings**
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

### 5. (Optional) Configure queue for notifications

If you're using **Sidekiq**, add the notification queue to your config:

```yaml
# config/sidekiq.yml
:queues:
  - error_notifications
  - default
  - mailers
```

If you're using **Solid Queue** (Rails 8.1+), add to your config:

```yaml
# config/queue.yml
workers:
  - queues: error_notifications
    threads: 3
    processes: 1
  - queues: default
    threads: 5
    processes: 1
```

**Note:** If you're using the default `async` adapter or other backends, no additional configuration is needed. The gem works with all ActiveJob adapters out of the box.

### 6. Visit the dashboard

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

  # === Notification Settings ===

  # Slack notifications
  config.enable_slack_notifications = true
  config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  # Email notifications
  config.enable_email_notifications = true
  config.notification_email_recipients = ENV.fetch('ERROR_NOTIFICATION_EMAILS', '').split(',').map(&:strip)
  config.notification_email_from = ENV.fetch('ERROR_NOTIFICATION_FROM', 'errors@example.com')

  # Dashboard base URL (for notification links)
  config.dashboard_base_url = ENV['DASHBOARD_BASE_URL']

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

# Slack notifications
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Email notifications (comma-separated list)
ERROR_NOTIFICATION_EMAILS=dev-team@example.com,ops@example.com
ERROR_NOTIFICATION_FROM=errors@myapp.com

# Dashboard URL (used in notification links)
DASHBOARD_BASE_URL=https://myapp.com

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

### Frontend & Mobile Error Reporting

Rails Error Dashboard can track errors from **any frontend or mobile application** - not just your Rails backend!

**Supported platforms:**
- 📱 **React Native** (iOS & Android)
- ⚛️ **React** (Web)
- 🅰️ **Angular**
- 💚 **Vue.js**
- 📱 **Flutter** (via HTTP)
- 📱 **Swift/Kotlin** (Native apps)
- 🌐 **Any JavaScript/TypeScript** application

#### Quick Setup

**1. Create an API endpoint in your Rails app:**

```ruby
# app/controllers/api/v1/mobile_errors_controller.rb
module Api
  module V1
    class MobileErrorsController < BaseController
      def create
        mobile_error = MobileError.new(error_params)

        RailsErrorDashboard::Commands::LogError.call(
          mobile_error,
          {
            current_user: current_user,
            request: request,
            source: :mobile_app  # or :react, :vue, :angular, etc.
          }
        )

        render json: { success: true }, status: :created
      end

      private

      def error_params
        params.require(:error).permit(:error_type, :message, :stack, :component)
      end

      class MobileError < StandardError
        attr_reader :mobile_data
        def initialize(data)
          @mobile_data = data
          super(data[:message])
        end
        def backtrace
          @mobile_data[:stack]&.split("\n") || []
        end
      end
    end
  end
end
```

**2. Report errors from your frontend:**

```javascript
// React/React Native/Vue/Angular
async function reportError(error, component) {
  try {
    await fetch('/api/v1/mobile_errors', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({
        error: {
          error_type: error.name,
          message: error.message,
          stack: error.stack,
          component: component
        }
      })
    });
  } catch (e) {
    console.error('Failed to report error:', e);
  }
}

// Usage in React component
try {
  // Your code
} catch (error) {
  reportError(error, 'UserProfile');
  // Handle error in UI
}
```

**3. Add Error Boundary (React/React Native):**

```jsx
class ErrorBoundary extends React.Component {
  componentDidCatch(error, errorInfo) {
    reportError(error, errorInfo.componentStack);
  }

  render() {
    return this.props.children;
  }
}
```

**Benefits:**
- ✅ **Single dashboard** for all errors (backend + frontend + mobile)
- ✅ **Platform detection** - errors automatically tagged by source
- ✅ **User tracking** - errors associated with logged-in users
- ✅ **Real-time notifications** - Slack/Email alerts for frontend errors too
- ✅ **Component tracking** - know which component/screen errored
- ✅ **Stack traces** - full JavaScript stack traces

**📚 Complete Integration Guide:**

For detailed setup instructions including:
- Offline support and retry logic
- Batch error reporting
- React Native integration
- Error filtering and deduplication
- Best practices

See: [MOBILE_APP_INTEGRATION.md](MOBILE_APP_INTEGRATION.md)

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

### 📧 Notification System

Rails Error Dashboard includes a powerful multi-channel notification system to alert your team when errors occur.

#### Slack Notifications

Get instant alerts in Slack with rich, formatted messages including:
- Error type and message
- Environment (Production, Staging, etc.)
- Platform (iOS, Android, API)
- User information
- Request details
- Direct link to view full error in dashboard

**Setup:**

1. Create a Slack webhook URL:
   - Go to https://api.slack.com/messaging/webhooks
   - Create a new webhook for your channel
   - Copy the webhook URL

2. Configure in your app:
   ```bash
   # .env
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   DASHBOARD_BASE_URL=https://myapp.com
   ```

3. Enable in initializer (enabled by default):
   ```ruby
   config.enable_slack_notifications = true
   config.slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
   ```

**Slack Message Features:**
- 🎨 Beautifully formatted with color-coded blocks
- 📱 Platform emoji indicators (iOS 📱, Android 🤖, API 🔌)
- 👤 User and IP address tracking
- 🔗 Direct "View Details" button linking to dashboard
- ⏰ Timestamp with timezone

#### Email Notifications

Send detailed email alerts to your team with HTML and plain text versions.

**Email Features:**
- 📨 Beautiful HTML email template with your app's branding
- 📄 Plain text fallback for email clients
- 🎯 Send to multiple recipients
- 📊 Full error context including stack trace
- 🔗 One-click link to view in dashboard
- 🏷️ Environment and platform badges

**Setup:**

1. Configure recipients and sender:
   ```bash
   # .env
   ERROR_NOTIFICATION_EMAILS=dev-team@example.com,ops@example.com,alerts@example.com
   ERROR_NOTIFICATION_FROM=errors@myapp.com
   DASHBOARD_BASE_URL=https://myapp.com
   ```

2. Enable in initializer (enabled by default):
   ```ruby
   config.enable_email_notifications = true
   config.notification_email_recipients = ENV.fetch('ERROR_NOTIFICATION_EMAILS', '').split(',').map(&:strip)
   config.notification_email_from = ENV.fetch('ERROR_NOTIFICATION_FROM', 'errors@example.com')
   ```

3. Ensure your Rails app has ActionMailer configured:
   ```ruby
   # config/environments/production.rb
   config.action_mailer.delivery_method = :smtp
   config.action_mailer.smtp_settings = {
     address: 'smtp.sendgrid.net',
     port: 587,
     domain: 'myapp.com',
     user_name: ENV['SENDGRID_USERNAME'],
     password: ENV['SENDGRID_PASSWORD'],
     authentication: 'plain',
     enable_starttls_auto: true
   }
   ```

**Email Template Includes:**
- Error type and full message
- Environment badge (Production/Staging/Development)
- Platform badge (iOS/Android/API)
- Timestamp with timezone
- User email and IP address
- Request URL and parameters
- First 10 lines of stack trace
- Prominent "View Full Details" button

#### Disabling Notifications

You can selectively disable notifications:

```ruby
# Disable Slack only
config.enable_slack_notifications = false

# Disable email only
config.enable_email_notifications = false

# Disable both
config.enable_slack_notifications = false
config.enable_email_notifications = false
```

#### Notification Workflow

When an error occurs:
1. Error is logged to database
2. Notifications are sent **asynchronously** via background jobs
3. Your team receives alerts via configured channels
4. Team clicks link in notification to view full details
5. Error can be investigated and marked as resolved in dashboard

#### Queue Configuration

Notification jobs use the `:error_notifications` queue by default. This allows you to:
- Prioritize error notifications over other jobs
- Monitor notification delivery separately
- Configure different concurrency/workers for notifications

**Works with all ActiveJob backends:**
- ✅ **Solid Queue** (Rails 8.1+ default)
- ✅ **Sidekiq** (most popular)
- ✅ **Delayed Job**
- ✅ **Resque**
- ✅ **Async** (Rails default for development)
- ✅ **Inline** (for testing)

**Setup for Sidekiq:**

```ruby
# config/sidekiq.yml
:queues:
  - default
  - error_notifications  # Add this queue
  - mailers

# Optional: Higher priority for error notifications
:queues:
  - [error_notifications, 5]  # Process 5x more often
  - [default, 1]
  - [mailers, 1]
```

**Setup for Solid Queue (Rails 8.1+):**

```ruby
# config/queue.yml
dispatchers:
  batch_size: 500

workers:
  - queues: error_notifications
    threads: 3
    processes: 1
    polling_interval: 1
  - queues: default
    threads: 5
    processes: 1
    polling_interval: 5
```

**No additional setup needed for:**
- Async adapter (Rails default in development)
- Inline adapter (synchronous, for testing)
- Other adapters use the queue name automatically

**Background Jobs:**
- Notifications use `ActiveJob` and run in background
- Use dedicated `:error_notifications` queue
- Won't block or slow down your application
- Failed notifications are logged but don't raise errors
- Retries handled by your ActiveJob backend (Sidekiq, Solid Queue, etc.)

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
