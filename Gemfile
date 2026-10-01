source "https://rubygems.org"

# Specify your gem's dependencies in rails_error_dashboard.gemspec.
gemspec

# Allow testing against different Rails versions via RAILS_VERSION env var
# Use pessimistic version to get latest patch versions (e.g. ~> 7.0.0 gets latest 7.0.x)
rails_version = ENV["RAILS_VERSION"] || "~> 8.1.0"
rails_version = "~> #{rails_version}.0" if rails_version =~ /^\d+\.\d+$/
gem "rails", rails_version

# json 3.0 (2026-09-07) raises ArgumentError on options that older Rails
# versions still pass: `quirks_mode` on 7.0-8.0, and a positional options hash
# in ActiveSupport::JSON.decode on 8.1 before 8.1.4 (breaks every session/flash
# read). Rails 8.1.4 and 7.2.4 carry the fix (rails/rails#58601, #58685); 8.0,
# 7.1 and 7.0 never will. CI deletes Gemfile.lock and resolves "~> 7.2.0" /
# "~> 8.1.0" to the latest patch, so those rows test json 3, as host apps on a
# fixed Rails get it. Every other requirement (older series, an exact
# version) keeps the pin.
gem "json", "< 3" unless rails_version.match?(/\A~> (7\.2|8\.1)\.0\z/)

gem "puma"

# Adapters for the databases the README advertises. Neither is loaded by the
# dummy app unless DATABASE_URL points at one (see DEVELOPMENT.md).
gem "pg"
gem "trilogy"

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
# rack-attack is an OPTIONAL runtime dependency (the tracker is gated on
# defined?(Rack::Attack)), but it must be in the dev bundle so specs can drive
# the real middleware. Two rack-attack bugs shipped green (#170's blank
# discriminator, and the flush-visibility bug) precisely because no spec could
# exercise the gem itself and the fixtures had to guess at its behaviour.
gem "rack-attack", "~> 6.7"
gem "turbo-rails", "~> 2.0"
# Solid Queue is never loaded into the test process (RED branches on
# defined?(::SolidQueue), so loading it would change other specs). The contract
# spec runs its real config parser in a child process and checks that
# SolidQueueConfigCheck agrees with it. CI resolves the newest release on every
# run, so a Solid Queue change that breaks the check shows up here first.
# Solid Queue needs Rails 7.1+.
unless rails_env.start_with?("7.0") || rails_env.start_with?("~> 7.0")
  gem "solid_queue", require: false
end

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
