source "https://rubygems.org"

# Specify your gem's dependencies in rails_error_dashboard.gemspec.
gemspec

# Allow testing against different Rails versions via RAILS_VERSION env var
# Use pessimistic version to get latest patch versions (e.g. ~> 7.0.0 gets latest 7.0.x)
rails_version = ENV["RAILS_VERSION"] || "~> 8.1.0"
rails_version = "~> #{rails_version}.0" if rails_version =~ /^\d+\.\d+$/
gem "rails", rails_version

gem "puma"

gem "pg"

# SQLite3 - version depends on Rails version
# Rails 7.0-7.2 require ~> 1.4, Rails 8.0+ requires >= 2.1
rails_env = ENV["RAILS_VERSION"] || "8.1"
if rails_env.start_with?("7.") || rails_env.start_with?("~> 7.")
  gem "sqlite3", "~> 1.4"
else
  gem "sqlite3", ">= 2.1"
end

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Git hooks manager for pre-commit/pre-push quality checks
gem "lefthook", "~> 2.0", require: false

# Security audit for dependencies
gem "bundler-audit", require: false

# Optional gem dependencies — needed in development/test for full feature coverage
gem "browser", "~> 6.0"
gem "chartkick", "~> 5.0"
gem "httparty", ">= 0.24"
gem "turbo-rails", "~> 2.0"

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
