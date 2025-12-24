# frozen_string_literal: true

# Multi-version testing configuration
# This file documents the Rails versions we support and test against.
#
# To test locally against a specific Rails version, use:
#   RAILS_VERSION=7.0 bundle update && bundle exec rspec
#   RAILS_VERSION=7.1 bundle update && bundle exec rspec
#   RAILS_VERSION=7.2 bundle update && bundle exec rspec
#   RAILS_VERSION=8.0 bundle update && bundle exec rspec
#
# CI/CD testing is handled by .github/workflows/test.yml

# Rails 7.0 (Stable LTS)
appraise "rails-7.0" do
  gem "rails", "~> 7.0.0"
end

# Rails 7.1 (Stable)
appraise "rails-7.1" do
  gem "rails", "~> 7.1.0"
end

# Rails 7.2 (Stable)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
end

# Rails 8.0 (Latest)
appraise "rails-8.0" do
  gem "rails", "~> 8.0.0"
end
