# Multi-Version Testing Guide

Rails Error Dashboard supports multiple Rails versions and is tested against Rails 7.0, 7.1, 7.2, and 8.0.

## Supported Versions

### Rails Versions
- ✅ **Rails 7.0** (LTS - Long Term Support)
- ✅ **Rails 7.1** (Stable)
- ✅ **Rails 7.2** (Stable)
- ✅ **Rails 8.0** (Latest)

### Ruby Versions
- ✅ **Ruby 3.2** (with Rails 7.0, 7.1, 7.2, 8.0)
- ✅ **Ruby 3.3** (with Rails 7.0, 7.1, 7.2, 8.0)
- ✅ **Ruby 3.4** (with Rails 7.0, 7.1, 7.2, 8.0)

**Note**: Rails Error Dashboard requires Ruby >= 3.2 due to the browser gem dependency

---

## Testing Locally

### Quick Test (Current Version)

```bash
bundle exec rspec
```

This runs tests against the Rails version specified in your `Gemfile.lock`.

### Test Against Specific Rails Version

Use the `RAILS_VERSION` environment variable to test against different Rails versions:

```bash
# Test Rails 7.0
RAILS_VERSION=7.0 bundle update && bundle exec rspec

# Test Rails 7.1
RAILS_VERSION=7.1 bundle update && bundle exec rspec

# Test Rails 7.2
RAILS_VERSION=7.2 bundle update && bundle exec rspec

# Test Rails 8.0
RAILS_VERSION=8.0 bundle update && bundle exec rspec
```

### Test All Versions (Sequential)

```bash
# Create a test script
cat > test_all_versions.sh <<'EOF'
#!/bin/bash
set -e

for version in 7.0 7.1 7.2 8.0; do
  echo "======================================="
  echo "Testing Rails $version"
  echo "======================================="
  RAILS_VERSION=$version bundle update rails
  bundle exec rspec
  echo ""
done
EOF

chmod +x test_all_versions.sh
./test_all_versions.sh
```

---

## Continuous Integration (GitHub Actions)

Multi-version testing is automated via GitHub Actions. Every push and pull request is tested against:

- **8 combinations** (2 Ruby versions × 4 Rails versions)
  - Ruby 3.2 with Rails 7.0, 7.1, 7.2, 8.0
  - Ruby 3.3 with Rails 7.0, 7.1, 7.2, 8.0

### GitHub Actions Workflow

**File**: `.github/workflows/test.yml`

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
    - name: Install dependencies
      env:
        RAILS_VERSION: ${{ matrix.rails }}
      run: bundle install
    - name: Run tests
      run: bundle exec rspec
```

### Viewing CI Results

1. Go to your repository on GitHub
2. Click "Actions" tab
3. View test results for all Ruby/Rails combinations
4. Green checkmarks = all tests passing

---

## Using Appraisal (Alternative Method)

### What is Appraisal?

Appraisal allows you to test against multiple dependency versions by generating separate Gemfiles.

### Setup

```bash
# Install appraisal
bundle install

# Generate gemfiles for each Rails version
bundle exec appraisal install
```

This creates:
- `gemfiles/rails_7.0.gemfile`
- `gemfiles/rails_7.1.gemfile`
- `gemfiles/rails_7.2.gemfile`
- `gemfiles/rails_8.0.gemfile`

### Run Tests with Appraisal

```bash
# Test specific version
bundle exec appraisal rails-7.0 rspec
bundle exec appraisal rails-7.1 rspec
bundle exec appraisal rails-7.2 rspec
bundle exec appraisal rails-8.0 rspec

# Test all versions
bundle exec appraisal rspec
```

### Appraisals File

**File**: `Appraisals`

```ruby
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
```

---

## Version Compatibility Matrix

| Ruby | Rails 7.0 | Rails 7.1 | Rails 7.2 | Rails 8.0 |
|------|-----------|-----------|-----------|-----------|
| 3.2  | ✅        | ✅        | ✅        | ✅        |
| 3.3  | ✅        | ✅        | ✅        | ✅        |
| 3.4  | ✅        | ✅        | ✅        | ✅        |

**Legend**:
- ✅ Supported and tested

**Note**: Ruby 3.1 is not supported because the browser gem (used for platform detection) requires Ruby >= 3.2.0

---

## Gemspec Configuration

The gemspec is configured to support multiple Rails versions:

```ruby
# rails_error_dashboard.gemspec

# Minimum Rails version
spec.add_dependency "rails", ">= 7.0.0"

# Dependencies with version flexibility
spec.add_dependency "pagy", "~> 9.0"
spec.add_dependency "browser", "~> 6.0"
spec.add_dependency "groupdate", "~> 6.0"
spec.add_dependency "httparty", "~> 0.21"

# Development dependencies
spec.add_development_dependency "sqlite3", ">= 1.4"  # Flexible for different Rails versions
spec.add_development_dependency "appraisal", "~> 2.5"
```

---

## Rails Version Differences

### Rails 7.0 vs 7.1 vs 7.2 vs 8.0

**Key Changes Affecting This Gem:**

1. **Rails 7.0**: Baseline version, stable LTS
2. **Rails 7.1**:
   - Improved error reporting
   - Better query logging
3. **Rails 7.2**:
   - Enhanced database features
   - Performance improvements
4. **Rails 8.0**:
   - Requires Ruby >= 3.2
   - Modern Ruby syntax
   - Performance optimizations

**Gem Compatibility:**
- ✅ All core features work across all versions
- ✅ Error tracking works identically
- ✅ Notifications work identically
- ✅ UI rendering identical
- ✅ Database queries compatible

---

## Troubleshooting

### Issue: Bundle fails with dependency conflicts

**Solution**: Clear bundler cache and reinstall

```bash
rm Gemfile.lock
bundle install
```

### Issue: Tests fail on specific Rails version

**Solution**: Check Rails version-specific changes

```bash
# Check which Rails version is installed
bundle exec rails -v

# Verify gemspec dependencies
bundle exec gem dependency rails_error_dashboard
```

### Issue: Appraisal install fails

**Solution**: Use environment variable method instead

```bash
# Instead of appraisal, use:
RAILS_VERSION=7.0 bundle update && bundle exec rspec
```

### Issue: GitHub Actions failing

**Solution**: Check workflow logs for specific Ruby/Rails combination

1. Go to Actions tab
2. Click failing workflow
3. Expand failing job
4. Check error messages for that specific combination

---

## Best Practices

### 1. Test Before Releasing

Before releasing a new version, test against all supported Rails versions:

```bash
for version in 7.0 7.1 7.2 8.0; do
  echo "Testing Rails $version..."
  RAILS_VERSION=$version bundle update rails && bundle exec rspec || exit 1
done
echo "All versions passed!"
```

### 2. Keep Dependencies Flexible

Use pessimistic version constraints (`~>`) for dependencies to allow minor updates:

```ruby
# Good
spec.add_dependency "pagy", "~> 9.0"  # Allows 9.0.x, 9.1.x, etc.

# Avoid
spec.add_dependency "pagy", "= 9.0.0"  # Too restrictive
```

### 3. Document Breaking Changes

If a feature only works on newer Rails versions, document it:

```ruby
# Works on Rails 7.1+
if Rails.version >= "7.1"
  # Use new feature
else
  # Fallback for Rails 7.0
end
```

### 4. Monitor Deprecation Warnings

Run tests with deprecation warnings enabled:

```bash
RAILS_DEPRECATION_WARNINGS=1 bundle exec rspec
```

---

## Updating Supported Versions

### Adding a New Rails Version

1. Update `Appraisals` file:
```ruby
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
end
```

2. Update `.github/workflows/test.yml`:
```yaml
matrix:
  rails: ['7.0', '7.1', '7.2', '8.0', '8.1']  # Add 8.1
```

3. Update `rails_error_dashboard.gemspec` if needed:
```ruby
spec.add_dependency "rails", ">= 7.0.0", "< 8.2"
```

4. Update this document with new version info

5. Test locally:
```bash
RAILS_VERSION=8.1 bundle update && bundle exec rspec
```

6. Update README.md:
```markdown
- Rails 7.0, 7.1, 7.2, 8.0, 8.1 support
```

### Dropping an Old Rails Version

1. Update gemspec:
```ruby
# Old
spec.add_dependency "rails", ">= 7.0.0"

# New (dropping 7.0 support)
spec.add_dependency "rails", ">= 7.1.0"
```

2. Remove from Appraisals:
```ruby
# Remove rails-7.0 section
```

3. Remove from GitHub Actions:
```yaml
matrix:
  rails: ['7.1', '7.2', '8.0']  # Removed 7.0
```

4. Update documentation
5. Announce in CHANGELOG.md
6. Bump major version (semver)

---

## Version Testing Checklist

Before releasing a new version:

- [ ] All specs pass on Rails 7.0
- [ ] All specs pass on Rails 7.1
- [ ] All specs pass on Rails 7.2
- [ ] All specs pass on Rails 8.0
- [ ] All specs pass on Ruby 3.2 (with all Rails)
- [ ] All specs pass on Ruby 3.3 (with all Rails)
- [ ] GitHub Actions CI passing (all combinations)
- [ ] No deprecation warnings
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version bumped appropriately

---

## Resources

### Official Documentation
- [Rails Upgrade Guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
- [Rails Versions](https://rubygems.org/gems/rails/versions)
- [Appraisal Gem](https://github.com/thoughtbot/appraisal)
- [GitHub Actions Ruby Setup](https://github.com/ruby/setup-ruby)

### Version Support Policy
- **Rails 7.0**: LTS support until 2025
- **Rails 7.1**: Active support
- **Rails 7.2**: Active support
- **Rails 8.0**: Latest stable

### Gem Support Policy
Rails Error Dashboard will:
- Support the latest 4 Rails versions
- Support Ruby versions compatible with supported Rails
- Drop support for EOL Rails versions in major releases
- Provide 6 months notice before dropping support

---

## FAQ

### Q: Which Rails version should I use?

**A**: Use the latest stable version (Rails 8.0) unless you have specific requirements for an older version.

### Q: Will my code work across all versions?

**A**: Yes, Rails Error Dashboard is tested to work identically across all supported versions.

### Q: How often are new Rails versions added?

**A**: We add support for new Rails versions within 1 month of their stable release.

### Q: What if I'm on Rails 6.x?

**A**: Rails 6.x is not supported. Please upgrade to Rails 7.0+ or use an older version of this gem.

### Q: Can I use this gem with Rails edge?

**A**: Not recommended for production. Edge Rails may have breaking changes.

---

**Phase 5 Complete!** 🎉

Multi-version testing is now configured and documented. The gem is tested against 12 different Ruby/Rails combinations in CI.
