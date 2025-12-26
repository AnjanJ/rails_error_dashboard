# Multi-Version Testing Guide

Rails Error Dashboard supports multiple Rails versions and is tested against Rails 7.0, 7.1, 7.2, and 8.0.

## Table of Contents

- [Supported Versions](#supported-versions)
- [Quick Start](#quick-start)
- [Testing Locally](#testing-locally)
- [Continuous Integration](#continuous-integration)
- [Version Compatibility](#version-compatibility)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## Supported Versions

### Rails Versions
- ✅ **Rails 7.0** (LTS - Long Term Support)
- ✅ **Rails 7.1** (Stable)
- ✅ **Rails 7.2** (Stable)
- ✅ **Rails 8.0** (Latest)

### Ruby Versions
- ✅ **Ruby 3.2** (with Rails 7.0, 7.1, 7.2, 8.0)
- ✅ **Ruby 3.3** (with Rails 7.0, 7.1, 7.2, 8.0)

**Note**: Rails Error Dashboard requires **Ruby >= 3.2** due to the browser gem dependency.

**Why no Ruby 3.1?** The browser gem v6.x requires Ruby >= 3.2.0.

---

## Quick Start

### Installation

```bash
# Clone the repo
git clone https://github.com/AnjanJ/rails_error_dashboard.git
cd rails_error_dashboard

# Install dependencies (defaults to Rails 8.0)
bundle install

# Run tests
bundle exec rspec
```

### Test Specific Rails Version

```bash
# Test Rails 7.0
RAILS_VERSION=7.0 bundle install
RAILS_VERSION=7.0 bundle exec rspec

# Test Rails 8.0
RAILS_VERSION=8.0 bundle install
RAILS_VERSION=8.0 bundle exec rspec
```

---

## Testing Locally

### Single Version Test

```bash
# Test current Rails version
bundle exec rspec

# Test with coverage
ENFORCE_COVERAGE=true bundle exec rspec
```

### Test Against Specific Rails Version

Use the `RAILS_VERSION` environment variable:

```bash
# Rails 7.0
RAILS_VERSION=7.0 bundle install && bundle exec rspec

# Rails 7.1
RAILS_VERSION=7.1 bundle install && bundle exec rspec

# Rails 7.2
RAILS_VERSION=7.2 bundle install && bundle exec rspec

# Rails 8.0
RAILS_VERSION=8.0 bundle install && bundle exec rspec
```

### Test All Versions

```bash
#!/bin/bash
for version in 7.0 7.1 7.2 8.0; do
  echo "======================================="
  echo "Testing Rails $version"
  echo "======================================="
  RAILS_VERSION=$version bundle install || exit 1
  RAILS_VERSION=$version bundle exec rspec || exit 1
  echo ""
done
echo "✅ All versions passed!"
```

---

## Continuous Integration

### GitHub Actions Setup

Every push and pull request is tested against **8 combinations**:
- Ruby 3.2 × Rails 7.0, 7.1, 7.2, 8.0
- Ruby 3.3 × Rails 7.0, 7.1, 7.2, 8.0

**Configuration**: `.github/workflows/test.yml`

```yaml
name: Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.2', '3.3']
        rails: ['7.0', '7.1', '7.2', '8.0']

    name: Ruby ${{ matrix.ruby }} / Rails ${{ matrix.rails }}

    steps:
    - uses: actions/checkout@v4

    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: ${{ matrix.ruby }}
        bundler-cache: false  # Important: Fresh lockfile per Rails version

    - name: Install dependencies
      env:
        RAILS_VERSION: ${{ matrix.rails }}
      run: |
        rm -f Gemfile.lock  # Fresh lockfile per version
        bundle config set --local path 'vendor/bundle'
        bundle install --jobs 4 --retry 3

    - name: Run tests
      env:
        RAILS_VERSION: ${{ matrix.rails }}
        COVERAGE: false
      run: bundle exec rspec
```

### Why No Gemfile.lock?

We **don't commit `Gemfile.lock`** for this gem. Here's why:

**Problem**: Gemfile.lock with dynamic Rails versions causes deployment mode conflicts in CI.

**Solution**: Generate fresh lockfile for each Rails version.

**This is standard for multi-version gems**: Devise, Pundit, FactoryBot, etc. all skip Gemfile.lock.

### Viewing CI Results

```bash
# View recent CI runs
gh run list --workflow=test.yml --limit 5

# View specific run
gh run view <run-id>

# View job logs
gh run view <run-id> --log
```

---

## Version Compatibility

### Compatibility Matrix

| Ruby | Rails 7.0 | Rails 7.1 | Rails 7.2 | Rails 8.0 |
|------|-----------|-----------|-----------|-----------|
| 3.2  | ✅        | ✅        | ✅        | ✅        |
| 3.3  | ✅        | ✅        | ✅        | ✅        |

**All 8 combinations tested in CI!** [![Tests](https://github.com/AnjanJ/rails_error_dashboard/workflows/Tests/badge.svg)](https://github.com/AnjanJ/rails_error_dashboard/actions)

### Key Compatibility Notes

1. **Ruby 3.2+ required** - browser gem dependency
2. **concurrent-ruby pinned to < 1.3.5** - Rails 7.0 compatibility
3. **Rails 7.0.8+ used** - Bug fixes for Ruby 3.2+
4. **sqlite3 version is conditional** - Different versions for Rails 7.x vs 8.x

---

## Configuration

### Gemfile

```ruby
# rails_error_dashboard/Gemfile

# Dynamic Rails version based on RAILS_VERSION env var
rails_version = ENV["RAILS_VERSION"] || "~> 8.0.0"
rails_version = "~> #{rails_version}.1" if rails_version =~ /^\d+\.\d+$/
gem "rails", rails_version

# Conditional sqlite3 based on Rails version
rails_env = ENV["RAILS_VERSION"] || "8.0"
if rails_env.start_with?("7.") || rails_env.start_with?("~> 7.")
  gem "sqlite3", "~> 1.4"  # Rails 7.0-7.2
else
  gem "sqlite3", ">= 2.1"  # Rails 8.0+
end
```

### Gemspec

```ruby
# rails_error_dashboard.gemspec

# Minimum versions
spec.required_ruby_version = ">= 3.2.0"
spec.add_dependency "rails", ">= 7.0.0"

# Pinned for compatibility
spec.add_dependency "concurrent-ruby", "~> 1.3.0", "< 1.3.5"

# Flexible dependencies
spec.add_dependency "pagy", "~> 9.0"
spec.add_dependency "browser", "~> 6.0"
spec.add_dependency "groupdate", "~> 6.0"
spec.add_dependency "httparty", "~> 0.21"
```

### Why These Pins?

- **Ruby >= 3.2.0**: browser gem requirement
- **concurrent-ruby < 1.3.5**: Rails 7.0 compatibility
- **Rails 7.0.8+**: Bug fixes for Ruby 3.2+

---

## Troubleshooting

### Quick Fixes

**Bundle install fails?**
```bash
rm Gemfile.lock
bundle install
```

**Tests fail on specific Rails version?**
```bash
# Check Rails version
RAILS_VERSION=7.0 bundle exec rails -v

# Clear cache
rm -rf .bundle vendor/bundle
bundle install
```

**CI failing?**
1. Check [Actions tab](https://github.com/AnjanJ/rails_error_dashboard/actions)
2. Look for specific Ruby/Rails combination failing
3. Check logs for error messages
4. Common issues include: dependency conflicts, version incompatibilities, and platform-specific failures

### Common Issues

Common CI issues and their resolutions:
1. **Browser gem Ruby version incompatibility** - Requires Ruby >= 3.2.0
2. **SimpleCov blocking tests** - Set `COVERAGE=false` in CI
3. **concurrent-ruby 1.3.5+ breaking Rails 7.0** - Pinned to < 1.3.5
4. **Rails 7.0.0 DescendantsTracker bugs** - Use Rails 7.0.8+
5. **SQLite3 version conflicts** - Conditional versions per Rails
6. **Gemfile.lock platform issues** - Don't commit lockfile
7. **Bundler deployment mode conflicts** - Fresh lockfile per version

---

## Best Practices

### Before Releasing

Test all supported versions:

```bash
for version in 7.0 7.1 7.2 8.0; do
  echo "Testing Rails $version..."
  RAILS_VERSION=$version bundle install || exit 1
  RAILS_VERSION=$version bundle exec rspec || exit 1
done
```

### Version Testing Checklist

- [ ] All specs pass on Rails 7.0
- [ ] All specs pass on Rails 7.1
- [ ] All specs pass on Rails 7.2
- [ ] All specs pass on Rails 8.0
- [ ] All specs pass on Ruby 3.2 (all Rails)
- [ ] All specs pass on Ruby 3.3 (all Rails)
- [ ] GitHub Actions CI passing (8/8 combinations)
- [ ] No deprecation warnings
- [ ] CHANGELOG.md updated

### Monitor Deprecations

```bash
RAILS_DEPRECATION_WARNINGS=1 bundle exec rspec
```

---

## Resources

### Documentation
- [Rails Upgrade Guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
- [ruby/setup-ruby](https://github.com/ruby/setup-ruby)

### Compatibility
- [Ruby & Rails Compatibility Table](https://www.fastruby.io/blog/ruby/rails/versions/compatibility-table.html)
- [Rails and Ruby Compatibility in 2025](https://www.fastruby.io/blog/ruby-rails-compatibility-in-2025.html)

### Support Policy

Rails Error Dashboard will:
- Support the latest 4 Rails major/minor versions
- Support Ruby versions compatible with supported Rails
- Drop EOL Rails versions in major releases only
- Provide 6 months notice before dropping support

---

## FAQ

**Q: Which Rails version should I use in development?**
A: Use Rails 8.0 (latest) unless you have specific version requirements.

**Q: Why isn't Gemfile.lock committed?**
A: For multi-version gems, committed lockfiles conflict with CI matrix testing. We generate a fresh lockfile for each Rails version.

**Q: Can I use Rails 6.x?**
A: No, minimum is Rails 7.0. Rails 6.x reached EOL.

**Q: Why no Ruby 3.1?**
A: The browser gem requires Ruby >= 3.2.0.

**Q: How do I test locally without installing all versions?**
A: Use Docker or rely on CI. GitHub Actions tests all combinations for you.

---

**Multi-version testing complete!** 🎉

All 8 Ruby/Rails combinations tested in CI with comprehensive coverage across Rails 7.0 through 8.0.
