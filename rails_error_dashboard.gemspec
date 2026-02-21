require_relative "lib/rails_error_dashboard/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_error_dashboard"
  spec.version     = RailsErrorDashboard::VERSION
  spec.authors     = [ "Anjan Jagirdar" ]
  spec.email       = [ "anjan.jagirdar@gmail.com" ]
  spec.homepage    = "https://github.com/AnjanJ/rails_error_dashboard"
  spec.summary     = "Self-hosted Rails error monitoring — free, forever. Zero SaaS fees, zero lock-in."
  spec.description = "Own your errors. Own your stack. A fully open-source, self-hosted error dashboard " \
                     "for solo founders, indie hackers, and small teams. Professional error tracking with " \
                     "beautiful UI, multi-channel notifications (Slack, Email, Discord, PagerDuty), " \
                     "platform detection (iOS/Android/Web/API), and analytics. 5-minute setup, works " \
                     "out-of-the-box. Rails 7.0-8.1 compatible. ⚠️ BETA: API may change before v1.0.0. " \
                     "🎮 Live demo: https://rails-error-dashboard.anjan.dev (gandalf/youshallnotpass)"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.post_install_message = <<~MESSAGE
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      Rails Error Dashboard v#{RailsErrorDashboard::VERSION}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    🆕 First time? Quick start:
       rails generate rails_error_dashboard:install
       rails db:migrate
       # Add to config/routes.rb:
       mount RailsErrorDashboard::Engine => '/error_dashboard'

    🔄 Upgrading from v0.1.x?
       rails db:migrate
       📝 Changelog: https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md

    🎮 Live demo: https://rails-error-dashboard.anjan.dev
       (gandalf / youshallnotpass)

    📖 Full docs: https://github.com/AnjanJ/rails_error_dashboard
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MESSAGE

  spec.metadata["homepage_uri"] = "https://AnjanJ.github.io/rails_error_dashboard"
  spec.metadata["source_code_uri"] = "https://github.com/AnjanJ/rails_error_dashboard"
  spec.metadata["changelog_uri"] = "https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://AnjanJ.github.io/rails_error_dashboard"
  spec.metadata["bug_tracker_uri"] = "https://github.com/AnjanJ/rails_error_dashboard/issues"
  # spec.metadata["funding_uri"] = "https://github.com/sponsors/YourUsername" # Uncomment if you set up GitHub Sponsors

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
  # turbo-rails (~> 2.0) — real-time Turbo Stream updates (falls back to page refresh)

  # Pin concurrent-ruby for Rails 7.0 compatibility
  # Rails 7.0 had issues with concurrent-ruby 1.3.5+ which removed logger dependency
  # Fixed in Rails 7.0.10+ (https://github.com/rails/rails/pull/54264)
  # Allowing up to < 1.3.7 as tests pass with Rails 7.0.10+
  # See: https://github.com/rails/rails/issues/54271
  spec.add_dependency "concurrent-ruby", "~> 1.3.0", "< 1.3.7"

  # Development and testing dependencies
  spec.add_development_dependency "rspec-rails", "~> 7.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.4"
  spec.add_development_dependency "faker", "~> 3.0"
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.0"
  spec.add_development_dependency "shoulda-matchers", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  # Note: sqlite3 version is specified in Gemfile based on Rails version
  # Rails 7.0 requires ~> 1.4, Rails 8.0 requires >= 2.1
  spec.add_development_dependency "appraisal", "~> 2.5"

  # System tests (browser-based UI testing)
  spec.add_development_dependency "capybara", "~> 3.40"
  spec.add_development_dependency "cuprite", "~> 0.15"
end
