source "https://rubygems.org"

# Specify your gem's dependencies in rails_error_dashboard.gemspec.
gemspec

# Allow testing against different Rails versions via RAILS_VERSION env var
rails_version = ENV['RAILS_VERSION'] || '~> 8.0.0'
gem "rails", rails_version

gem "puma"

gem "pg"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
