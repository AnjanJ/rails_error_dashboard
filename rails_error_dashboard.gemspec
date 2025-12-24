require_relative "lib/rails_error_dashboard/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_error_dashboard"
  spec.version     = RailsErrorDashboard::VERSION
  spec.authors     = [ "Anjan Jagirdar" ]
  spec.email       = [ "anjan@example.com" ]
  spec.homepage    = "https://github.com/anjanjagirdar/rails_error_dashboard"
  spec.summary     = "Beautiful, production-ready error tracking dashboard for Rails applications"
  spec.description = "Rails Error Dashboard provides a complete error tracking solution with a beautiful UI, " \
                     "Slack notifications, platform detection (iOS/Android/API), analytics, and optional " \
                     "separate database support. Works seamlessly with Rails 7+ error reporting."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/anjanjagirdar/rails_error_dashboard"
  spec.metadata["changelog_uri"] = "https://github.com/anjanjagirdar/rails_error_dashboard/blob/main/CHANGELOG.md"

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
end
