---
layout: home
hero:
  name: Rails Error Dashboard
  text: Self-Hosted Error Tracking for Rails
  tagline: "Free, forever. Zero SaaS fees, zero lock-in. Professional error tracking for solo founders, indie hackers, and small teams."
  actions:
    - theme: brand
      text: Get Started
      link: /docs/quickstart/
    - theme: alt
      text: Live Demo
      link: https://rails-error-dashboard.anjan.dev
    - theme: alt
      text: GitHub
      link: https://github.com/AnjanJ/rails_error_dashboard
features:
  - icon: "\U0001F3A8"
    title: Beautiful UI
    details: Custom design system with dark/light mode, real-time updates, and responsive layout.
  - icon: "\U0001F4CA"
    title: Real-time Analytics
    details: Error trends, platform health, correlation insights, baseline monitoring, and occurrence patterns.
  - icon: "\U0001F514"
    title: Multi-Channel Notifications
    details: Slack, Email, Discord, PagerDuty, and custom webhooks with per-error throttling.
  - icon: "\U0001F4F1"
    title: Platform Detection
    details: iOS, Android, Web, and API with automatic categorization and platform-specific analytics.
  - icon: "\U0001F50D"
    title: Smart Grouping
    details: Advanced error correlation, cascade detection, fuzzy matching, and custom fingerprinting.
  - icon: "\U000026A1"
    title: High Performance
    details: Async logging, rate limiting, sampling, BRIN indexes, and database optimization built in.
  - icon: "\U0001F3AF"
    title: Zero Configuration
    details: Works out-of-the-box with sensible defaults. Full installer guides you through setup in 5 minutes.
  - icon: "\U0001F512"
    title: Self-Hosted
    details: Complete data ownership. Runs inside your Rails process — no external services, no data leaving your servers.
---

## Quick Start

```bash
# Add to Gemfile
gem 'rails_error_dashboard'

# Install
bundle install
rails generate rails_error_dashboard:install
rails db:migrate

# Route is added automatically by the generator
# Start your app and visit /red
```

## From the Community

> All three [self-hosted alternatives] had an issue with error backtrace when using Turbo — RED did fix it… solid_errors and Faultline are not very active projects, RED is very active and @AnjanJ is very responsive in fixing issues. So, RED was my final choice.
>
> — **Gael Marziou** ([@gmarziou](https://github.com/gmarziou)) · [discussion #116](https://github.com/AnjanJ/rails_error_dashboard/discussions/116)

## Why Rails Error Dashboard?

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

## Contributing

We welcome contributions! See our [GitHub repository](https://github.com/AnjanJ/rails_error_dashboard) for feature requests, bug reports, and pull requests.

## License

MIT License - see [LICENSE](https://github.com/AnjanJ/rails_error_dashboard/blob/main/MIT-LICENSE) for details.
