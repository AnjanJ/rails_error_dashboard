# Development Guide

Welcome to Rails Error Dashboard development! This guide will help you set up your environment and understand our development workflow.

## 🚀 Quick Start

### Prerequisites
- Ruby >= 3.2.0
- Bundler
- Git

### Setup
```bash
# Clone the repository
git clone https://github.com/AnjanJ/rails_error_dashboard.git
cd rails_error_dashboard

# Run automated setup
bin/setup
```

The setup script will:
- ✅ Install all dependencies
- ✅ Install Lefthook git hooks
- ✅ Setup test database
- ✅ Run tests to verify everything works

---

## 🪝 Git Hooks (Lefthook)

We use [Lefthook](https://github.com/evilmartians/lefthook) to ensure code quality **before** pushing to CI. This:
- ✅ **Saves CI minutes** (free tier has limits)
- ✅ **Provides faster feedback** (seconds vs minutes)
- ✅ **Catches issues early** (before CI fails)

### Hooks Installed

All hooks are defined in `lefthook.yml`, and every command runs through `bin/with-ruby`
so the hook uses the Ruby pinned in `.ruby-version`.

#### Pre-Commit (runs on `git commit`)
The hook is **piped**: stage 1 runs first, and stage 2 runs only if stage 1 passes.

Stage 1 — fast checks, scoped to what is staged:
- ✅ RuboCop on staged `.rb` files (generator templates excluded)
- ✅ RSpec on staged `*_spec.rb` files
- ✅ `bundle audit check --update` (vulnerable dependencies; runs on every commit)
- ✅ Debugger statements (`binding.pry`, `byebug`, `debugger`) in staged `.rb` files
- ✅ `bin/i18n-check`, when a locale file or the checker itself is staged
- ✅ Trailing whitespace in staged `.rb`, `.yml`, `.js` and `.md` files

Stage 2 — the pre-release chaos suite (`bin/pre-release-test all`): builds four temporary
Rails apps in production mode and runs the chaos phases against them. This is the slow part
(`lefthook.yml` puts it at ~4-5 minutes). Skip only this stage with
`LEFTHOOK_EXCLUDE=chaos-tests git commit -m "message"`.

#### Pre-Push
There is no pre-push hook. `lefthook.yml` leaves it disabled and relies on GitHub Actions
instead. (`bin/setup` still prints "pre-push" in its summary; that line is out of date.)

### Hook Commands

```bash
# Skip only the chaos stage (fast checks still run)
LEFTHOOK_EXCLUDE=chaos-tests git commit -m "message"

# Skip all hooks temporarily
LEFTHOOK=0 git commit -m "message"

# Run the pre-commit hook manually
lefthook run pre-commit

# Run all quality checks: RuboCop, the full RSpec suite, bundle audit
lefthook run qa

# Run quick checks (changed files only)
lefthook run quick

# Auto-fix RuboCop issues
lefthook run fix
```

---

## 🧪 Testing

### Run All Tests
```bash
bundle exec rspec
```

### Run Specific Test
```bash
bundle exec rspec spec/lib/rails_error_dashboard/commands/log_error_spec.rb
```

### Coverage
SimpleCov runs on every `bundle exec rspec` (`spec/spec_helper.rb` starts it
unconditionally; the `COVERAGE` variable the CI workflows set is not read).
`ENFORCE_COVERAGE=true` also fails the run below 80%.

```bash
bundle exec rspec
open coverage/index.html
```

### Directory Arguments Run Everything
`spec/spec_helper.rb` pins `config.pattern` to every spec under `spec/`, so
passing a directory — `bundle exec rspec spec/system/` included — runs the
whole suite. CI's system-test job does exactly that and reports the full
count. To leave the browser specs out, exclude them instead:

```bash
bundle exec rspec --exclude-pattern "spec/system/**/*"
```

### Testing on PostgreSQL or MySQL

The dummy app is configured for SQLite; `DATABASE_URL` overrides that, and on
any non-SQLite adapter the test schema is built from the gem's own migrations
(`RED_TEST_SCHEMA=migrations`, the default there) rather than from
`spec/dummy/db/schema.rb`:

```bash
createdb red_test
DATABASE_URL="postgres://localhost/red_test?pool=10" bundle exec rspec --exclude-pattern "spec/system/**/*"

mysql -uroot -e "create database red_test character set utf8mb4"
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -uroot mysql   # once per server; groupdate needs it
DATABASE_URL="trilogy://root@localhost/red_test?pool=10" bundle exec rspec --exclude-pattern "spec/system/**/*"
```

Migration specs (`spec/db/migrations`) run DDL, so they execute outside the
transactional wrapper and clean up by deletion. `bin/check-schema-parity`
compares `schema.rb` with the migrations on SQLite; CI runs it on every PR.

### Multi-Version Testing
```bash
# Gemfile.lock is gitignored and pinned to whichever Rails you last installed,
# so delete it before switching (CI deletes it for every matrix row too)
rm -f Gemfile.lock
RAILS_VERSION=7.0 bundle install
RAILS_VERSION=7.0 bundle exec rspec

# Back to the default (Rails 8.1)
rm -f Gemfile.lock
bundle install
```

See [docs/development/TESTING.md](docs/development/TESTING.md) for the full matrix.

---

## 🎨 Code Style

### RuboCop

We follow [Omakase Ruby Style Guide](https://github.com/rails/rubocop-rails-omakase).

```bash
# Check style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -A

# Check specific file
bundle exec rubocop lib/rails_error_dashboard/commands/log_error.rb
```

### Pre-Commit Hook
RuboCop runs automatically on staged `.rb` files when you commit. It does not
auto-correct: any offense blocks the commit. Run `bundle exec rubocop -A` to fix
what can be fixed automatically, then stage the result.

---

## 🔒 Security

### Bundle Audit

Check for vulnerable dependencies:

```bash
# Update vulnerability database
bundle audit update

# Check for vulnerabilities
bundle audit check

# The pre-commit hook runs `bundle audit check --update` on every commit
```

---

## 📊 CI/CD Workflow

### Local Development (You)
```
1. Make changes
2. git commit → pre-commit hook: fast checks on staged files, then the chaos suite
3. git push   → no hook; GitHub Actions runs on the pull request
```

### GitHub Actions (CI)

A pull request to `main` gets 22 checks from two workflows:

- **`.github/workflows/ci.yml`**
  - `lint` — RuboCop and `bin/i18n-check`
  - `Integration Tests (shared + separate DB)` — `bin/full-integration-test all`
  - `Upgrade Path (published → this branch)` — `bin/pre-release-test full_upgrade`.
    The job always reports, but it only does the work on release PRs and on PRs
    that touch `db/migrate/`
- **`.github/workflows/test.yml`**
  - RSpec, system specs excluded, on Ruby 3.2, 3.3 and 3.4 × Rails 7.0, 7.1,
    7.2, 8.0 and 8.1 (15 jobs, SQLite)
  - PostgreSQL 16 and MySQL 8.4 on Ruby 3.4 / Rails 8.1, with the test schema
    built from the gem's own migrations (`RED_TEST_SCHEMA=migrations`)
  - `Schema parity (schema.rb vs db/migrate)` — `bin/check-schema-parity`
  - `System Tests (Chrome)` — Ruby 3.4 / Rails 8.1

On pushes to `main`, `release.yml` runs release-please (merging its release PR
publishes the gem to RubyGems) and `pages.yml` deploys the documentation site.

---

## 🚦 Development Workflow

### 1. Create Feature Branch
```bash
git checkout -b feature/amazing-feature
```

### 2. Make Changes
Edit files, add features, fix bugs...

### 3. Run Tests
```bash
bundle exec rspec
```

### 4. Commit Changes
```bash
git add .
git commit -m "feat: add amazing feature"
# Pre-commit hook runs automatically
```

### 5. Push to GitHub
```bash
git push origin feature/amazing-feature
# No pre-push hook; CI runs on the pull request
```

### 6. Create Pull Request
GitHub Actions CI will run and should pass!

---

## 🐛 Troubleshooting

### Hooks Not Running

```bash
# Reinstall hooks
bundle exec lefthook install

# Check hooks are installed
ls -la .git/hooks/
```

### Hooks Too Slow

The chaos stage is the slow part of the pre-commit hook.

```bash
# Skip only the chaos stage (fast checks still run)
LEFTHOOK_EXCLUDE=chaos-tests git commit -m "WIP"

# Skip all hooks temporarily
LEFTHOOK=0 git commit -m "WIP"

# Run quick checks instead of the full suite
lefthook run quick
```

### RuboCop Fails

```bash
# Auto-fix issues
bundle exec rubocop -A

# Check what will be fixed
bundle exec rubocop -A --dry-run
```

### Tests Fail

```bash
# Run specific failing test
bundle exec rspec spec/path/to/failing_spec.rb:42

# Run with verbose output
bundle exec rspec --format documentation

# Check test database
RAILS_ENV=test bundle exec rails db:reset
```

---

## 📚 Additional Resources

### Documentation
- [Main README](README.md) - Gem documentation
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [docs/](docs/) - Feature documentation

### Testing
- [docs/development/TESTING.md](docs/development/TESTING.md) - Multi-version testing guide

### Tools
- [Lefthook Documentation](https://github.com/evilmartians/lefthook/blob/master/docs/usage.md)
- [RuboCop Documentation](https://docs.rubocop.org/)
- [RSpec Documentation](https://rspec.info/)

---

## 💡 Tips for Contributors

### Save CI Minutes
- ✅ Let the pre-commit hook run
- ✅ Use `lefthook run qa` (RuboCop, full RSpec, bundle audit) before pushing large changes
- ✅ Fix RuboCop issues locally (`rubocop -A`)

### Fast Development
- ✅ Use `lefthook run quick` for changed files only
- ✅ Run specific tests during development
- ✅ Use `--fail-fast` to stop on first failure

### Quality Code
- ✅ Write tests for new features
- ✅ Follow conventional commit messages
- ✅ Keep commits focused and atomic
- ✅ Update documentation when needed

---

## ⚙️ Configuration Files

### Key Files
- `lefthook.yml` - Git hooks configuration
- `.rubocop.yml` - Code style rules
- `Gemfile` - Dependencies
- `.github/workflows/` - CI configuration

### Lefthook Configuration
Hooks live in `lefthook.yml`. An excerpt of the pre-commit hook:
```yaml
pre-commit:
  piped: true  # stage 1 first; the chaos tests only run if it passes

  commands:
    rubocop-staged:
      priority: 1
      glob: "*.rb"
      exclude:
        - "lib/generators/**/templates/*"
      run: bin/with-ruby bundle exec rubocop {staged_files}
```

---

## 🤝 Getting Help

- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Slack**: Run tests locally first, hooks will help!

---

**Happy coding!** 🎉

The hooks are here to help, not hinder. They catch issues early and save everyone time!
