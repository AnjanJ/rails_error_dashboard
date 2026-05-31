# frozen_string_literal: true

# Multi-version testing configuration
# This file documents the Rails versions we support and test against.
#
# To test locally against a specific Rails version, use:
#   RAILS_VERSION=7.0 bundle update && RAILS_VERSION=7.0 bundle exec rspec
#   RAILS_VERSION=7.1 bundle update && RAILS_VERSION=7.1 bundle exec rspec
#   RAILS_VERSION=7.2 bundle update && RAILS_VERSION=7.2 bundle exec rspec
#   RAILS_VERSION=8.0 bundle update && RAILS_VERSION=8.0 bundle exec rspec
#   RAILS_VERSION=8.1 bundle update && RAILS_VERSION=8.1 bundle exec rspec
#
# CI/CD testing is handled by .github/workflows/test.yml

# Rails 7.0 (Stable LTS) - Use latest patch version for Ruby 3.2+ compat
appraise "rails-7.0" do
  gem "rails", "~> 7.0.8"
end

# Rails 7.1 (Stable)
appraise "rails-7.1" do
  gem "rails", "~> 7.1.0"
end

# Rails 7.2 (Stable)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
end

# Rails 8.0 (Stable)
appraise "rails-8.0" do
  gem "rails", "~> 8.0.0"
end

# Rails 8.1 (Latest)
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
end
