---
layout: home
hero:
  name: Rails Error Dashboard
  text: Self-Hosted Error Tracking for Rails
  tagline: "Records what your process looked like when it failed — GC, memory, DB pool, Puma, job queues — on the error itself, inside your app, in your own database. The gem is MIT and free forever."
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
  - icon: "\U0001F52C"
    title: The Moment of Failure
    details: GC, memory, file descriptors, load, DB pool, Puma, job queues and YJIT captured at the latest occurrence and stored on the error record — no other tracker attaches them to the error.
  - icon: "\U0001F4CA"
    title: Analytics
    details: Error trends, platform health, correlation insights, baseline monitoring, and occurrence patterns.
  - icon: "\U0001F514"
    title: Multi-Channel Notifications
    details: Slack, Email, Discord, PagerDuty, and custom webhooks with per-error throttling.
  - icon: "\U0001F4F1"
    title: Platform Detection
    details: iOS, Android and API detected from the User-Agent, with platform-specific analytics.
  - icon: "\U0001F50D"
    title: Smart Grouping
    details: Advanced error correlation, cascade detection, fuzzy matching, and custom fingerprinting.
  - icon: "\U000026A1"
    title: High Performance
    details: Async logging, rate limiting, sampling, BRIN indexes, and database optimization built in.
  - icon: "\U0001F3AF"
    title: 5-Minute Setup
    details: Sensible defaults out of the box; the installer walks you through the optional features. Dark/light mode, live updates with turbo-rails.
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

### What nothing else records
- **The state of the process at the moment of failure** - GC, memory, file descriptors, load, the ActiveRecord pool, Puma, job queues, RubyVM/YJIT — stored on the error record, then correlated across errors. Every APM has these as graphs; none attaches them to the error
- **What error trackers don't watch** - swallowed exceptions with a raise-vs-rescue ratio per location, production deprecations, Rack::Attack events and the AI crawlers behind them
- **An error you can run** - Copy as RSpec generates a request spec from the captured request; no other tracker generates a test
- **Storm accounting** - per-fingerprint caps, an exact count-only circuit breaker and a Storm History ledger, on by default

### Inside your app
- **Self-hosted** - Runs inside your Rails process; error data never leaves your infrastructure. A self-hosted Sentry alternative for teams that can't send errors to a third party
- **Native Rails integration** - Works with Rails 7.0-8.1, Ruby 3.2-4.0, on PostgreSQL, MySQL/Trilogy or SQLite
- **Multi-channel alerts** - Slack, Email, Discord, PagerDuty, webhooks; issues in GitHub, GitLab, Codeberg or Linear
- **Fully customizable** - Extend with plugins and custom handlers

### The gem is MIT and free forever
- **No RED licence or event-ingestion fee** - the gem costs nothing to run
- **No plan limits** - your database is the only cap; storm protection sheds context during floods by design

Checked against Sentry, Honeybadger, AppSignal, Rollbar, Bugsnag, Airbrake, Raygun, New Relic, Datadog, Scout, Skylight and every self-hosted Rails tracker in August 2026 — [the verified ledger](https://github.com/AnjanJ/rails_error_dashboard/blob/main/.shipkit/research/red-unique-features-verified.md).

## Contributing

We welcome contributions! See our [GitHub repository](https://github.com/AnjanJ/rails_error_dashboard) for feature requests, bug reports, and pull requests.

## License

MIT License - see [LICENSE](https://github.com/AnjanJ/rails_error_dashboard/blob/main/MIT-LICENSE) for details.
