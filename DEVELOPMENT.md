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

#### Pre-Commit (Fast - runs on `git commit`)
Runs ONLY on staged files (< 2 seconds):
- ✅ RuboCop on changed files
- ✅ Check for debugger statements
- ✅ Ruby syntax validation
- ✅ Trailing whitespace check

#### Pre-Push (Comprehensive - runs on `git push`)
Mirrors CI checks (~1-2 minutes):
- ✅ RuboCop on entire codebase
- ✅ Full RSpec test suite
- ✅ Bundle audit (security check)
- ✅ Check for uncommitted changes

### Hook Commands

```bash
# Skip hooks temporarily
LEFTHOOK=0 git commit -m "message"
git push --no-verify

# Run hooks manually
lefthook run pre-commit
lefthook run pre-push

# Run all quality checks (like CI)
lefthook run qa

# Run quick checks (changed files only)
lefthook run quick

# Auto-fix RuboCop issues
lefthook run fix

# Multi-version testing (Rails 7.0-8.0)
lefthook run multi-version
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

### Run With Coverage
```bash
COVERAGE=true bundle exec rspec
open coverage/index.html
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
# Test against specific Rails version
RAILS_VERSION=7.0 bundle install
RAILS_VERSION=7.0 bundle exec rspec

# Or use Lefthook
lefthook run multi-version
```

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
RuboCop runs automatically on changed files when you commit. It will:
- Auto-fix simple issues
- Block commit if critical issues found
- Stage fixed files automatically

---

## 🔒 Security

### Bundle Audit

Check for vulnerable dependencies:

```bash
# Update vulnerability database
bundle audit update

# Check for vulnerabilities
bundle audit check

# This runs automatically on pre-push hook
```

---

## 📊 CI/CD Workflow

### Local Development (You)
```
1. Make changes
2. Pre-commit hook runs → Fast checks
3. git push
4. Pre-push hook runs → Full CI mirror
5. Push to GitHub (only if all checks pass)
```

### GitHub Actions (CI)
```
1. Runs same checks as pre-push hook
2. Multi-version testing (Rails 7.0-8.0, Ruby 3.2-3.3)
3. Deployment (if on main branch)
```

**Result:** CI almost always passes because local hooks caught issues!

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
# Pre-push hook runs automatically (mirrors CI)
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

```bash
# Skip hooks temporarily
LEFTHOOK=0 git commit -m "WIP"
git push --no-verify

# Run quick checks instead of full suite
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
- ✅ Always let pre-push hooks run (they mirror CI)
- ✅ Use `lefthook run qa` before pushing large changes
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
Edit `lefthook.yml` to customize hooks:
```yaml
pre-commit:
  commands:
    rubocop-changed:
      run: bundle exec rubocop {staged_files}
      stage_fixed: true  # Auto-stage fixes
```

---

## 🤝 Getting Help

- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Slack**: Run tests locally first, hooks will help!

---

**Happy coding!** 🎉

The hooks are here to help, not hinder. They catch issues early and save everyone time!
