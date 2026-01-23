---
layout: default
title: Home
---

# Rails Error Dashboard

**Self-hosted Rails error monitoring — free, forever. Zero SaaS fees, zero lock-in.**

Own your errors. Own your stack. A fully open-source, self-hosted error dashboard for solo founders, indie hackers, and small teams. Professional error tracking with beautiful UI, multi-channel notifications (Slack, Email, Discord, PagerDuty), platform detection (iOS/Android/Web/API), and analytics. 5-minute setup, works out-of-the-box. Rails 7.0-8.1 compatible.

## 🎮 Live Demo

Try the dashboard: [https://rails-error-dashboard.anjan.dev](https://rails-error-dashboard.anjan.dev)

**Credentials:** `gandalf` / `youshallnotpass`

## 🚀 Quick Start

```bash
# Add to Gemfile
gem 'rails_error_dashboard'

# Install
bundle install
rails generate rails_error_dashboard:install
rails db:migrate

# Mount in config/routes.rb
mount RailsErrorDashboard::Engine => '/error_dashboard'

# Start your app and visit /error_dashboard
```

## ✨ Key Features

- **🎨 Beautiful UI** - Modern Bootstrap 5 design with dark/light mode
- **📊 Real-time Analytics** - Error trends, platform health, correlation insights
- **🔔 Multi-Channel Notifications** - Slack, Email, Discord, PagerDuty, Webhooks
- **📱 Platform Detection** - iOS, Android, Web, API with automatic categorization
- **🔍 Smart Grouping** - Advanced error correlation and pattern detection
- **⚡ High Performance** - Async logging, rate limiting, database optimization
- **🎯 Zero Configuration** - Works out-of-the-box with sensible defaults
- **🔒 Self-Hosted** - Complete data ownership, no external dependencies

## 📚 Documentation

- [**Quickstart Guide**](docs/QUICKSTART) - Get started in 5 minutes
- [**Features Overview**](docs/FEATURES) - Comprehensive feature list
- [**Multi-App Support**](docs/MULTI_APP_PERFORMANCE) - Centralized monitoring
- [**API Reference**](docs/API_REFERENCE) - Full API documentation
- [**Customization**](docs/CUSTOMIZATION) - Tailor to your needs
- [**Plugin System**](docs/PLUGIN_SYSTEM) - Extend functionality
- [**Troubleshooting**](docs/TROUBLESHOOTING) - Common issues

## 🛠️ Installation

```ruby
gem 'rails_error_dashboard'
```

Then run:

```bash
rails generate rails_error_dashboard:install
```

The installer will guide you through:
- Multi-channel notifications setup (Slack, Email, Discord, PagerDuty)
- Database configuration (shared or separate database)
- Advanced features (error correlation, platform comparison, etc.)

## 📦 What's New in v0.1.32

- ✨ Enhanced overview dashboard with 6 key metrics
- 📊 Correlation insights section
- ⚙️ Better default configuration (retention: nil, backtrace: 100 lines)
- 🎨 Improved color contrast for accessibility
- 🐛 Fixed Chart.js v4 compatibility
- 🔗 Added bug tracker metadata for RubyGems

[View Full Changelog](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md)

## 💎 Why Rails Error Dashboard?

### Free Forever
- **$0/month** - No subscription fees, ever
- **Unlimited errors** - No caps, no tiers, no billing surprises
- **Self-hosted** - Complete control over your data

### Professional Features
- **Enterprise-grade monitoring** without enterprise pricing
- **Multi-channel alerts** to keep your team informed
- **Advanced analytics** for deep error insights
- **Beautiful UI** that rivals commercial solutions

### Built for Rails
- **Native Rails integration** - Works with Rails 7.0-8.1
- **Zero configuration** - Sensible defaults, works out-of-the-box
- **Performance optimized** - Async logging, smart caching
- **Fully customizable** - Extend with plugins and custom handlers

## 🤝 Contributing

We welcome contributions! See our [GitHub repository](https://github.com/AnjanJ/rails_error_dashboard) for:
- Feature requests and bug reports
- Pull requests and code contributions
- Documentation improvements

## 📄 License

MIT License - see [LICENSE](https://github.com/AnjanJ/rails_error_dashboard/blob/main/MIT-LICENSE) for details.

## 🔗 Links

- [GitHub Repository](https://github.com/AnjanJ/rails_error_dashboard)
- [RubyGems Page](https://rubygems.org/gems/rails_error_dashboard)
- [Live Demo](https://rails-error-dashboard.anjan.dev)
- [Issue Tracker](https://github.com/AnjanJ/rails_error_dashboard/issues)
- [Changelog](https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md)

---

**Made with ❤️ for the Rails community**
