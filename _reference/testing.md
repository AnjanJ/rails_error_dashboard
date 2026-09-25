---
layout: default
title: "Multi-Version Testing Guide"
order: 7
---

# Multi-Version Testing Guide

Rails Error Dashboard supports multiple Rails versions and is tested against Rails 7.0, 7.1, 7.2, 8.0, and 8.1, on SQLite, PostgreSQL and MySQL.

## Table of Contents

- [Supported Versions](#supported-versions)
- [Quick Start](#quick-start)
- [Testing Locally](#testing-locally)
- [Testing on PostgreSQL and MySQL](#testing-on-postgresql-and-mysql)
- [Continuous Integration](#continuous-integration)
- [Other Test Suites](#other-test-suites)
- [Version Compatibility](#version-compatibility)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## Supported Versions

### Rails Versions
- ✅ **Rails 7.0** (LTS - Long Term Support)
- ✅ **Rails 7.1** (Stable)
- ✅ **Rails 7.2** (Stable)
- ✅ **Rails 8.0** (Stable)
- ✅ **Rails 8.1** (Latest)

### Ruby Versions
- ✅ **Ruby 3.2** (with Rails 7.0, 7.1, 7.2, 8.0, 8.1)
- ✅ **Ruby 3.3** (with Rails 7.0, 7.1, 7.2, 8.0, 8.1)
- ✅ **Ruby 3.4** (with Rails 7.0, 7.1, 7.2, 8.0, 8.1)
- ✅ **Ruby 4.0** (with Rails 8.1) — verified by the maintainer; not yet in the CI matrix

**Note**: Rails Error Dashboard requires **Ruby >= 3.2** (`required_ruby_version` in the gemspec). The optional browser gem (v6) has the same floor.

**Ruby 3.3+ features**: Swallowed exception detection (`TracePoint(:rescue)`) requires Ruby 3.3+. These specs are conditionally skipped on Ruby 3.2.

---

## Quick Start

### Installation

```bash
# Clone the repo
git clone https://github.com/AnjanJ/rails_error_dashboard.git
cd rails_error_dashboard

# Install dependencies (defaults to Rails 8.1)
bundle install

# Run tests
bundle exec rspec
```

### Test Specific Rails Version

```bash
# Gemfile.lock is gitignored and pinned to whichever Rails you last installed,
# so delete it before switching (CI does the same for every matrix row)
rm -f Gemfile.lock
RAILS_VERSION=7.0 bundle install
RAILS_VERSION=7.0 bundle exec rspec

# Back to the default (Rails 8.1)
rm -f Gemfile.lock
bundle install
```

---

## Testing Locally

### Single Version Test

```bash
# Test current Rails version (everything, system specs included)
bundle exec rspec

# Leave out the browser (system) specs, as the CI matrix does
bundle exec rspec --exclude-pattern "spec/system/**/*"

# Also fail the run if coverage drops below 80%
ENFORCE_COVERAGE=true bundle exec rspec
```

SimpleCov runs on every invocation and writes `coverage/index.html`. The `COVERAGE`
variable that the CI workflows set is not read by the suite.

**A directory argument does not narrow the run.** `spec/spec_helper.rb` pins
`config.pattern` to every spec under `spec/`, so `bundle exec rspec spec/system/`
runs the whole suite. CI's system-test job runs exactly that command and reports the
full example count. Use `--exclude-pattern` to leave specs out.

### Test Against Specific Rails Version

Set `RAILS_VERSION` on **both** commands. Without it, the Gemfile asks for the default
Rails 8.1, which no longer matches the lockfile you just installed:

```bash
# Rails 7.0
rm -f Gemfile.lock && RAILS_VERSION=7.0 bundle install && RAILS_VERSION=7.0 bundle exec rspec

# Rails 7.1
rm -f Gemfile.lock && RAILS_VERSION=7.1 bundle install && RAILS_VERSION=7.1 bundle exec rspec

# Rails 7.2
rm -f Gemfile.lock && RAILS_VERSION=7.2 bundle install && RAILS_VERSION=7.2 bundle exec rspec

# Rails 8.0
rm -f Gemfile.lock && RAILS_VERSION=8.0 bundle install && RAILS_VERSION=8.0 bundle exec rspec

# Rails 8.1
rm -f Gemfile.lock && RAILS_VERSION=8.1 bundle install && RAILS_VERSION=8.1 bundle exec rspec
```

### Test All Versions

```bash
#!/bin/bash
for version in 7.0 7.1 7.2 8.0 8.1; do
  echo "======================================="
  echo "Testing Rails $version"
  echo "======================================="
  rm -f Gemfile.lock
  RAILS_VERSION=$version bundle install || exit 1
  RAILS_VERSION=$version bundle exec rspec || exit 1
  echo ""
done
rm -f Gemfile.lock && bundle install   # back to the default Rails 8.1
echo "✅ All versions passed!"
```

---

## Testing on PostgreSQL and MySQL

The dummy app's `spec/dummy/config/database.yml` is SQLite. Setting `DATABASE_URL`
overrides it with no config change, and the `pg` and `trilogy` adapters are already in
the Gemfile. On any adapter other than SQLite, the test schema is built from the gem's
own migrations in `db/migrate` (`RED_TEST_SCHEMA=migrations`, the default there; see
`spec/support/test_schema.rb`) — which is what a host app installs — rather than from
`spec/dummy/db/schema.rb`.

**PostgreSQL**

```bash
createdb red_test
DATABASE_URL="postgres://localhost/red_test?pool=10" bundle exec rspec --exclude-pattern "spec/system/**/*"
```

**MySQL**

```bash
mysql -uroot -e "create database red_test character set utf8mb4"
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -uroot mysql   # once per server; groupdate needs the time zone tables
DATABASE_URL="trilogy://root@localhost/red_test?pool=10" bundle exec rspec --exclude-pattern "spec/system/**/*"
```

`pool=10` and the excluded system specs match what the CI PostgreSQL and MySQL rows use.
`RED_TEST_SCHEMA` (`schema` or `migrations`) overrides the default schema source.
`bin/check-schema-parity` compares `schema.rb` with the migrations on SQLite so the two
don't drift; CI runs it on every pull request.

---

## Continuous Integration

### GitHub Actions Setup

Every pull request to `main` gets **22 checks** from two workflows.

**`.github/workflows/test.yml`**

| Job | What runs |
|-----|-----------|
| `Ruby X / Rails Y` (15 jobs) | RSpec without the system specs, on SQLite: Ruby 3.2, 3.3, 3.4 × Rails 7.0, 7.1, 7.2, 8.0, 8.1 |
| `postgresql / Ruby 3.4 / Rails 8.1` | The same suite on PostgreSQL 16, schema built from `db/migrate` |
| `mysql / Ruby 3.4 / Rails 8.1` | The same suite on MySQL 8.4 with its time zone tables loaded, schema built from `db/migrate` |
| `Schema parity (schema.rb vs db/migrate)` | `bin/check-schema-parity` |
| `System Tests (Chrome)` | `bundle exec rspec spec/system/` on Ruby 3.4 / Rails 8.1 — which runs the whole suite, system specs included (see the note above) |

**`.github/workflows/ci.yml`**

| Job | What runs |
|-----|-----------|
| `lint` | RuboCop and `bin/i18n-check` |
| `Integration Tests (shared + separate DB)` | `bin/full-integration-test all` |
| `Upgrade Path (published → this branch)` | `bin/pre-release-test full_upgrade`. The job always reports, but only does the work on release PRs and on PRs that touch `db/migrate/` |

Each Ruby × Rails job starts from a fresh lockfile and schema. An excerpt of
`.github/workflows/test.yml` (the file itself is the source of truth):

```yaml
    - name: Install dependencies
      env:
        RAILS_VERSION: ${{ matrix.rails }}
      run: |
        rm -f Gemfile.lock
        bundle config set --local path 'vendor/bundle'
        bundle install --jobs 4 --retry 3

    - name: Setup test database
      env:
        RAILS_VERSION: ${{ matrix.rails }}
      run: |
        mkdir -p spec/dummy/db
        cd spec/dummy
        rm -f db/*.sqlite3
        RAILS_ENV=test bundle exec rake db:schema:load
        cd ../..

    - name: Run unit and integration tests
      env:
        RAILS_VERSION: ${{ matrix.rails }}
        COVERAGE: false
      run: bundle exec rspec --exclude-pattern "spec/system/**/*"
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

## Other Test Suites

These build real Rails apps and run them in production mode, rather than testing inside
the dummy app:

- `bin/pre-release-test all` — the chaos suite, four apps (sync, async, HTTP, separate
  database). The pre-commit hook runs it. Its summary counts five runs, because the HTTP
  app records two (Phase F and Phase D). On 2026-09-25 it ran 1,483 assertions.
- `bin/pre-release-test release_audit` — all eight apps: the four above plus kitchen
  sink, multi-app, Solid Queue and upgrade path.
- `bin/pre-release-test full_upgrade` — installs the latest published gem, then upgrades
  to the working copy. CI runs it on release PRs.
- `bin/full-integration-test all` — HTTP-level tests against every dashboard page, in a
  shared-database and a separate-database app. CI runs it on every pull request.

---

## Version Compatibility

### Compatibility Matrix

| Ruby | Rails 7.0 | Rails 7.1 | Rails 7.2 | Rails 8.0 | Rails 8.1 |
|------|-----------|-----------|-----------|-----------|-----------|
| 3.2  | ✅        | ✅        | ✅        | ✅        | ✅        |
| 3.3  | ✅        | ✅        | ✅        | ✅        | ✅        |
| 3.4  | ✅        | ✅        | ✅        | ✅        | ✅        |

**All 15 combinations tested in CI!** PostgreSQL and MySQL are tested on Ruby 3.4 / Rails 8.1. [![Tests](https://github.com/AnjanJ/rails_error_dashboard/workflows/Tests/badge.svg)](https://github.com/AnjanJ/rails_error_dashboard/actions)

### Key Compatibility Notes

1. **Ruby 3.2+ required** - `required_ruby_version` in the gemspec
2. **concurrent-ruby is `~> 1.3`, with no upper pin** - the old ceiling was removed; on Rails 7.0 the real boundary is 7.0.10+ (see the comment in the gemspec)
3. **json is pinned `< 3` in the Gemfile** - json 3.0 breaks released Rails versions
4. **sqlite3 version is conditional** - Different versions for Rails 7.x vs 8.x

---

## Configuration

### Gemfile

An excerpt of `Gemfile`:

```ruby
# Dynamic Rails version based on RAILS_VERSION env var (default: Rails 8.1)
rails_version = ENV["RAILS_VERSION"] || "~> 8.1.0"
rails_version = "~> #{rails_version}.0" if rails_version =~ /^\d+\.\d+$/
gem "rails", rails_version

# json 3.0 raises on options that released Rails versions still pass
gem "json", "< 3"

# PostgreSQL and MySQL adapters; the dummy app only uses them when DATABASE_URL points at one
gem "pg"
gem "trilogy"

# Conditional sqlite3 based on Rails version
rails_env = ENV["RAILS_VERSION"] || "8.1"
if rails_env.start_with?("7.") || rails_env.start_with?("~> 7.")
  gem "sqlite3", "~> 1.4"  # Rails 7.0-7.2
else
  gem "sqlite3", ">= 2.1"  # Rails 8.0+
end
```

### Gemspec

An excerpt of `rails_error_dashboard.gemspec`:

```ruby
# Minimum versions
spec.required_ruby_version = ">= 3.2.0"
spec.add_dependency "rails", ">= 7.0.0"

# Required runtime dependencies
spec.add_dependency "pagy", "~> 43.0"
spec.add_dependency "groupdate", "~> 6.0"
spec.add_dependency "concurrent-ruby", "~> 1.3"

# Optional, not gemspec dependencies (features degrade gracefully without them):
# browser (~> 6.0), chartkick (~> 5.0), httparty (>= 0.24), turbo-rails (~> 2.0)
```

### Why These Pins?

- **Ruby >= 3.2.0**: the gemspec's `required_ruby_version`
- **concurrent-ruby `~> 1.3`**: matches how Rails itself depends on it. The earlier ceiling did not protect Rails 7.0 (the boundary is Rails 7.0.10+ whatever the concurrent-ruby version) and held users on a release with known CVEs — the gemspec comment has the detail
- **json `< 3`**: json 3.0 breaks every released Rails version, and the Rails 7.x line will never get the fix — the Gemfile comment has the detail

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
2. **SimpleCov blocking tests** - Coverage is only enforced with `ENFORCE_COVERAGE=true`, which CI does not set
3. **Rails 7.0 failing to boot with a `Logger` NameError** - Use Rails 7.0.10+; no concurrent-ruby pin fixes it
4. **Rails 7.0.0 DescendantsTracker bugs** - Use Rails 7.0.8+
5. **SQLite3 version conflicts** - Conditional versions per Rails
6. **Gemfile.lock platform issues** - Don't commit lockfile
7. **Bundler deployment mode conflicts** - Fresh lockfile per version
8. **json 3.0 breaking every matrix row** - Pinned `< 3` in the Gemfile

---

## Best Practices

### Before Releasing

Test all supported versions:

```bash
for version in 7.0 7.1 7.2 8.0 8.1; do
  echo "Testing Rails $version..."
  rm -f Gemfile.lock
  RAILS_VERSION=$version bundle install || exit 1
  RAILS_VERSION=$version bundle exec rspec || exit 1
done
```

### Version Testing Checklist

- [ ] All specs pass on Rails 7.0
- [ ] All specs pass on Rails 7.1
- [ ] All specs pass on Rails 7.2
- [ ] All specs pass on Rails 8.0
- [ ] All specs pass on Rails 8.1
- [ ] All specs pass on Ruby 3.2 (all Rails)
- [ ] All specs pass on Ruby 3.3 (all Rails)
- [ ] All specs pass on Ruby 3.4 (all Rails)
- [ ] All specs pass on PostgreSQL and MySQL
- [ ] GitHub Actions CI passing (all 22 checks)
- [ ] No deprecation warnings
- [ ] Commit types correct — release-please writes CHANGELOG.md from them; it is not edited by hand

### Monitor Deprecations

There is no dedicated switch: nothing in the suite reads a `RAILS_DEPRECATION_WARNINGS`
variable. Check the output of a normal `bundle exec rspec` run.

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
A: Use Rails 8.1 (latest) unless you have specific version requirements.

**Q: Why isn't Gemfile.lock committed?**
A: For multi-version gems, committed lockfiles conflict with CI matrix testing. We generate a fresh lockfile for each Rails version.

**Q: Can I use Rails 6.x?**
A: No, minimum is Rails 7.0. Rails 6.x reached EOL.

**Q: Why no Ruby 3.1?**
A: The gemspec requires Ruby >= 3.2.0 (as does the optional browser gem, v6).

**Q: How do I test locally without installing all versions?**
A: Use Docker or rely on CI. GitHub Actions tests all combinations for you.

---

**Multi-version testing complete!** 🎉

All 15 Ruby/Rails combinations tested in CI across Rails 7.0 through 8.1 on Ruby 3.2, 3.3, and 3.4, plus PostgreSQL and MySQL rows on Ruby 3.4 / Rails 8.1.
