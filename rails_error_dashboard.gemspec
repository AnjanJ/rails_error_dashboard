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
                     "out-of-the-box. Rails 7.0-8.1 compatible. ⚠️ BETA: API may change before v1.0.0."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/AnjanJ/rails_error_dashboard"
  spec.metadata["changelog_uri"] = "https://github.com/AnjanJ/rails_error_dashboard/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # Rails dependencies
  spec.add_dependency "rails", ">= 7.0.0"

  # Pagination
  spec.add_dependency "pagy", ">= 9", "< 44"

  # Platform detection
  spec.add_dependency "browser", "~> 6.0"

  # Grouping and time-based queries
  spec.add_dependency "groupdate", "~> 6.0"

  # HTTP client for notifications (Discord, PagerDuty, Webhooks)
  spec.add_dependency "httparty", "~> 0.21"

  # Real-time updates via Turbo Streams
  spec.add_dependency "turbo-rails", "~> 2.0"

  # Pin concurrent-ruby for Rails 7.0 compatibility
  # Rails 7.0 has issues with concurrent-ruby 1.3.5+ which removed logger dependency
  # See: https://github.com/rails/rails/issues/54271
  spec.add_dependency "concurrent-ruby", "~> 1.3.0", "< 1.3.5"

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
end
