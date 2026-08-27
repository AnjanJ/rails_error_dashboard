require_relative "lib/rails_error_dashboard/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_error_dashboard"
  spec.version     = RailsErrorDashboard::VERSION
  spec.authors     = [ "Anjan Jagirdar" ]
  spec.email       = [ "anjan.jagirdar@gmail.com" ]
  spec.homepage    = "https://AnjanJ.github.io/rails_error_dashboard"
  spec.summary     = "Self-hosted error tracking inside your Rails app. Captures GC, memory, DB-pool, " \
                     "Puma and job-queue state on every error, plus local and instance variables, " \
                     "swallowed exceptions and storm-safe accounting. No external service. MIT."
  spec.description = "Own your errors. Own your stack. A fully open-source, self-hosted error tracking " \
                     "Rails engine that runs entirely inside your own process, with no external " \
                     "services and zero recurring cost. " \
                     "Captures what no other tracker attaches to the error: a snapshot of the process " \
                     "at the moment of failure (GC, memory, threads, connection pool, Puma, job queues, " \
                     "RubyVM/YJIT), plus local and instance variables (via TracePoint), exception cause " \
                     "chains, swallowed-exception detection with raise-vs-rescue analysis, and breadcrumbs. " \
                     "Turn an error into a runnable RSpec test, a curl command, an LLM prompt, or a " \
                     "two-way-synced issue in GitHub, GitLab, Codeberg or Linear. " \
                     "Plus N+1 query detection, storm protection (per-fingerprint caps, an exact " \
                     "count-only circuit breaker and a storm ledger, ON by default), multi-app support, " \
                     "error sampling, and async logging via Sidekiq or SolidQueue. " \
                     "Runs on SQLite, PostgreSQL, or MySQL/Trilogy — in your app's existing database " \
                     "or an isolated separate error database. Dashboard UI (dark/light), " \
                     "multi-channel notifications (Slack, Email, Discord, PagerDuty, webhooks), " \
                     "workflow management, analytics, platform detection, LLM observability with no " \
                     "prompt capture, bring-your-own-key AI help, and OpenTelemetry span export. " \
                     "The dashboard, mailers and notification payloads are translated into 11 " \
                     "languages: English, German, Spanish, French, Brazilian Portuguese, Italian, " \
                     "Polish, Russian, Ukrainian, Japanese, and Simplified Chinese — 1,515 source " \
                     "strings, set via config.dashboard_locale with a per-user picker. RED " \
                     "translates through its own private I18n backend and never mutates your app's " \
                     "I18n; a missing translation falls back to English. Backtraces, exception " \
                     "names and webhook payload keys stay English by design. The ten non-English " \
                     "locales are machine-translated and not yet reviewed by native speakers. " \
                     "5-minute setup, works out-of-the-box. Rails 7.0-8.1, Ruby 3.2-4.0. " \
                     "BETA: API may change before v1.0.0. " \
                     "Live demo: https://rails-error-dashboard.anjan.dev (gandalf/youshallnotpass)"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.post_install_message = <<~MESSAGE
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      RED (Rails Error Dashboard) v#{RailsErrorDashboard::VERSION}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    First install:
       rails generate rails_error_dashboard:install
       rails db:migrate
       # Route and config are set up automatically by the generator.

    Upgrading from a previous version:
       rails generate rails_error_dashboard:install
       rails db:migrate
       # The generator detects your existing config and only adds new migrations.

    Separate database users:
       rails generate rails_error_dashboard:install
       rails db:migrate:error_dashboard
       # See docs for full separate-DB setup.

    Live demo: https://rails-error-dashboard.anjan.dev
    Full docs:  https://github.com/AnjanJ/rails_error_dashboard
    Changelog:  https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MESSAGE

  spec.metadata["homepage_uri"] = "https://AnjanJ.github.io/rails_error_dashboard"
  spec.metadata["source_code_uri"] = "https://github.com/AnjanJ/rails_error_dashboard"
  spec.metadata["changelog_uri"] = "https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://AnjanJ.github.io/rails_error_dashboard"
  spec.metadata["bug_tracker_uri"] = "https://github.com/AnjanJ/rails_error_dashboard/issues"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/AnjanJ"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # Rails dependencies
  spec.add_dependency "rails", ">= 7.0.0"

  # Pagination
  spec.add_dependency "pagy", "~> 43.0"

  # Grouping and time-based queries
  spec.add_dependency "groupdate", "~> 6.0"

  # Optional dependencies — features degrade gracefully without these:
  # browser (~> 6.0)    — richer platform detection (falls back to regex)
  # chartkick (~> 5.0)  — chart helpers (falls back to CDN-only JS)
  # httparty (>= 0.24)  — Discord/PagerDuty/webhook notifications (falls back to Net::HTTP)
  # turbo-rails (~> 2.0) — real-time Turbo Stream updates (without it the dashboard does not auto-refresh)

  # concurrent-ruby powers the storm-protection primitives (AtomicReference,
  # AtomicFixnum, Map) — a real runtime dependency, not incidental.
  #
  # This was previously pinned to "< 1.3.7" for Rails 7.0 compatibility:
  # concurrent-ruby 1.3.5 dropped its `logger` dependency, which broke
  # ActiveSupport on Rails < 7.0.10 (rails/rails#54271, fixed in
  # rails/rails#54264).
  #
  # That ceiling was removed because it did not do what it claimed. Verified
  # empirically on Ruby 3.2 and 3.4: Rails 7.0.8.7 raises
  # `uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger`
  # with concurrent-ruby 1.3.4 and 1.3.6 as well — both of which the old pin
  # ALLOWED. The real boundary is Rails 7.0.10+, independent of the
  # concurrent-ruby version, so the ceiling protected nobody while forcing
  # every user onto 1.3.6, which carries three CVEs fixed in 1.3.7:
  # CVE-2026-54904 (AtomicReference#update livelock on Float::NAN),
  # CVE-2026-54905 (ReentrantReadWriteLock read-count overflow),
  # CVE-2026-54906 (ReadWriteLock thread-safety).
  #
  # For the record, none of the three is reachable through OUR code: the single
  # AtomicReference (count_buffer.rb) only ever holds a Concurrent::Map, never
  # a Float, and we use no ReadWriteLock at all. The reason not to hold users
  # on 1.3.6 is their OTHER gems, plus the bundle-audit noise it generates in
  # every downstream app.
  #
  # "~> 1.3" matches how Rails itself depends on concurrent-ruby (~> 1.0,
  # >= 1.3.1) rather than being stricter than the framework. An upper bound in
  # a Rails ENGINE is especially costly — it becomes an unsatisfiable-conflict
  # generator against every other gem in the host app. New installs resolve to
  # 1.3.8; existing lockfiles are free to stay where they are.
  spec.add_dependency "concurrent-ruby", "~> 1.3"

  # Development and testing dependencies
  spec.add_development_dependency "rspec-rails", "~> 7.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.4"
  spec.add_development_dependency "faker", "~> 3.0"
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.0"
  spec.add_development_dependency "shoulda-matchers", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "simplecov", "~> 1.1"
  # Note: sqlite3 version is specified in Gemfile based on Rails version
  # Rails 7.0 requires ~> 1.4, Rails 8.0 requires >= 2.1
  spec.add_development_dependency "appraisal", "~> 2.5"

  # System tests (browser-based UI testing)
  spec.add_development_dependency "capybara", "~> 3.40"
  spec.add_development_dependency "cuprite", "~> 0.15"
end
