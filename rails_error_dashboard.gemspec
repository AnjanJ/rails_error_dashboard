require_relative "lib/rails_error_dashboard/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_error_dashboard"
  spec.version     = RailsErrorDashboard::VERSION
  spec.authors     = [ "Anjan Jagirdar" ]
  spec.email       = [ "anjan@example.com" ]
  spec.homepage    = "https://github.com/AnjanJ/rails_error_dashboard"
  spec.summary     = "Beautiful error tracking dashboard for Rails applications (BETA)"
  spec.description = "⚠️ BETA: Rails Error Dashboard provides error tracking with a beautiful UI, " \
                     "multi-channel notifications (Slack, Email, Discord, PagerDuty), platform detection " \
                     "(iOS/Android/Web/API), analytics, and optional separate database support. " \
                     "Works with Rails 7.0-8.0. API may change before v1.0.0."
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
  spec.add_dependency "pagy", "~> 9.0"

  # Platform detection
  spec.add_dependency "browser", "~> 6.0"

  # Grouping and time-based queries
  spec.add_dependency "groupdate", "~> 6.0"

  # HTTP client for notifications (Discord, PagerDuty, Webhooks)
  spec.add_dependency "httparty", "~> 0.21"

  # Development and testing dependencies
  spec.add_development_dependency "rspec-rails", "~> 7.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.4"
  spec.add_development_dependency "faker", "~> 3.0"
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.0"
  spec.add_development_dependency "shoulda-matchers", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "sqlite3", ">= 1.4"
  spec.add_development_dependency "appraisal", "~> 2.5"
end
