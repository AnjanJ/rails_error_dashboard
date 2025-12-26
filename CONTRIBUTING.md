# Contributing to Rails Error Dashboard

First off, thank you for considering contributing to Rails Error Dashboard! It's people like you that make this gem better for everyone.

Following these guidelines helps communicate that you respect the time of the developers managing and developing this open source project. In return, they should reciprocate that respect in addressing your issue, assessing changes, and helping you finalize your pull requests.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
- [Testing](#testing)
- [Code Style](#code-style)
- [Commit Messages](#commit-messages)
- [Documentation](#documentation)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to [your contact method - replace this].

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the [existing issues](https://github.com/AnjanJ/rails_error_dashboard/issues) as you might find that the issue has already been reported. When you are creating a bug report, please include as many details as possible using our [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml).

**Good bug reports should include:**

- **Clear title** - A descriptive summary of the issue
- **Steps to reproduce** - Numbered steps that recreate the problem
- **Expected behavior** - What you expected to happen
- **Actual behavior** - What actually happened
- **Environment details** - Gem version, Rails version, Ruby version, database
- **Stack trace** - Full error backtrace if applicable
- **Additional context** - Screenshots, configuration snippets, or related issues

**Note:** If you find a **security vulnerability**, do NOT open an issue. Please follow our [Security Policy](.github/SECURITY.md) instead.

### Suggesting Features

Feature suggestions are welcome! Before creating a feature request:

1. **Check existing feature requests** - Someone may have already suggested it
2. **Check the roadmap** - It might already be planned
3. **Consider scope** - Does this fit the project's goals?

When suggesting a feature, please use our [feature request template](.github/ISSUE_TEMPLATE/feature_request.yml) and include:

- **Problem statement** - What problem does this solve?
- **Proposed solution** - How should it work?
- **Alternatives** - What other approaches did you consider?
- **Use case** - Real-world example of when this would be useful

**Tip:** Opening an issue to discuss the feature BEFORE starting work saves time and ensures alignment with the project's direction.

### Pull Requests

Pull requests are the best way to propose changes to the codebase. We actively welcome your pull requests!

**Before You Start:**

1. **Open an issue first** (for significant changes) - Discuss your approach before investing time
2. **One feature per PR** - Separate pull requests for unrelated changes
3. **Check existing PRs** - Someone might already be working on it

**Pull Request Process:**

1. **Fork the repository** and create your branch from `main`
   ```bash
   git clone https://github.com/YOUR-USERNAME/rails_error_dashboard.git
   cd rails_error_dashboard
   git checkout -b feature/my-awesome-feature
   ```

2. **Make your changes** following our [development guidelines](#development-setup)

3. **Add tests** - Pull requests without tests will not be accepted
   - Bug fixes: Add a failing test that now passes
   - New features: Add tests demonstrating the feature works
   - Refactoring: Ensure existing tests still pass

4. **Update documentation**
   - Update README.md if adding user-facing features
   - Add/update guides in `docs/` for detailed features
   - Add RDoc comments for complex code
   - Update CHANGELOG.md (see [CHANGELOG Guidelines](#changelog-guidelines))

5. **Run the full test suite** and ensure everything passes
   ```bash
   bundle exec rspec
   ```

6. **Run RuboCop** and fix any offenses
   ```bash
   bundle exec rubocop
   # Or auto-fix most issues:
   bundle exec rubocop -A
   ```

7. **Ensure tests pass on all supported versions** (optional but appreciated)
   ```bash
   bundle exec rake test:all_versions
   ```

8. **Push to your fork** and submit a pull request
   ```bash
   git push origin feature/my-awesome-feature
   ```

9. **Fill out the PR template** completely - This helps reviewers understand your changes

**Pull Request Requirements (Checklist):**

Your PR must meet these requirements:

- [ ] **Tests included** - All code changes have corresponding tests
- [ ] **Tests pass** - `bundle exec rspec` runs without failures
- [ ] **RuboCop passes** - `bundle exec rubocop` shows no offenses
- [ ] **Documentation updated** - README, guides, or code comments updated
- [ ] **CHANGELOG updated** - Entry added to `[Unreleased]` section (unless docs/tests only)
- [ ] **One feature per PR** - Unrelated changes belong in separate PRs
- [ ] **Clean commit history** - Squash "WIP" or "fix typo" commits
- [ ] **Up-to-date with main** - Rebase on latest main branch

**Note:** The pre-commit hooks (via Lefthook) will automatically check RuboCop and run tests. If you need to skip hooks temporarily: `LEFTHOOK=0 git commit -m "message"`

## Development Setup

### Prerequisites

- **Ruby** 3.2+ (we test on 3.2, 3.3, 3.4)
- **Rails** 7.0+ (we support 7.0, 7.1, 7.2, 8.0, 8.1)
- **Bundler** 2.0+
- **SQLite3** (for test database)
- **Git**

### Setup Steps

1. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR-USERNAME/rails_error_dashboard.git
   cd rails_error_dashboard
   ```

2. **Add upstream remote** (to keep your fork in sync)
   ```bash
   git remote add upstream https://github.com/AnjanJ/rails_error_dashboard.git
   ```

3. **Install dependencies**
   ```bash
   bundle install
   ```

4. **Set up the test database**
   ```bash
   cd spec/dummy
   RAILS_ENV=test bundle exec rails db:create db:migrate
   cd ../..
   ```

5. **Install Lefthook** (git hooks for quality checks)
   ```bash
   bundle exec lefthook install
   ```

6. **Run tests to verify setup**
   ```bash
   bundle exec rspec
   ```

   You should see all tests passing ✅

### Keeping Your Fork Updated

```bash
# Fetch latest changes from upstream
git fetch upstream

# Merge upstream changes into your main branch
git checkout main
git merge upstream/main

# Push updates to your fork
git push origin main
```

## Testing

We have comprehensive test coverage and require tests for all changes.

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lib/rails_error_dashboard/commands/log_error_spec.rb

# Run specific test (by line number)
bundle exec rspec spec/lib/rails_error_dashboard/commands/log_error_spec.rb:42

# Run with coverage report
COVERAGE=true bundle exec rspec
```

### Test Coverage

We use SimpleCov to track test coverage. After running tests with `COVERAGE=true`, open `coverage/index.html` in your browser to see the coverage report.

**Guidelines:**
- Maintain or improve existing coverage percentage
- New features should have 90%+ coverage
- Bug fixes must include tests that would have caught the bug

### Writing Tests

We use RSpec. Follow these conventions:

```ruby
# Good test structure
RSpec.describe RailsErrorDashboard::Commands::LogError do
  describe ".call" do
    context "when error is new" do
      it "creates error log" do
        expect {
          described_class.call(exception: StandardError.new("test"))
        }.to change(RailsErrorDashboard::ErrorLog, :count).by(1)
      end
    end

    context "when error already exists" do
      it "increments occurrence count" do
        # Test implementation
      end
    end
  end
end
```

**Test Naming:**
- Use `describe` for methods/classes
- Use `context` for different scenarios
- Use `it` for expected behavior
- Be descriptive - tests are documentation

## Code Style

We follow the [Ruby Style Guide](https://rubystyle.guide/) via RuboCop with the Rails Omakase configuration.

### Checking Style

```bash
# Check all files
bundle exec rubocop

# Check specific files/directories
bundle exec rubocop app/models/

# Auto-fix issues (when safe)
bundle exec rubocop -A
```

### Style Guidelines

**Key conventions:**
- 2 spaces for indentation (no tabs)
- UTF-8 encoding
- Unix line endings (LF, not CRLF)
- Maximum line length: 120 characters
- Trailing newline at end of files
- No trailing whitespace

**Ruby conventions:**
- Use `snake_case` for methods and variables
- Use `CamelCase` for classes and modules
- Use `SCREAMING_SNAKE_CASE` for constants
- Use `?` suffix for predicate methods (return boolean)
- Use `!` suffix for dangerous methods (modify in-place)

**Rails conventions:**
- Follow Rails naming conventions for models, controllers, migrations
- Use ActiveRecord query interface (avoid raw SQL when possible)
- Use strong parameters in controllers

### Pre-commit Hooks

Lefthook automatically runs these checks on commit:
- RuboCop (full codebase check)
- RSpec (full test suite)
- Bundle audit (security vulnerabilities)
- Debugger statement check
- Trailing whitespace check

**To skip hooks temporarily:**
```bash
LEFTHOOK=0 git commit -m "message"
# or
git commit --no-verify -m "message"
```

## Commit Messages

Good commit messages help reviewers understand your changes and make the git history more useful.

### Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Example:**
```
feat(notifications): add Discord webhook support

Adds Discord notification channel similar to existing Slack integration.
Includes configuration options for webhook URL and message customization.

Closes #123
```

### Types

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, no logic change)
- `refactor:` - Code refactoring (no feature change)
- `perf:` - Performance improvements
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks (dependencies, build, etc.)
- `ci:` - CI/CD changes

### Guidelines

- **Use present tense** - "Add feature" not "Added feature"
- **Be concise** - 50 chars or less for subject line
- **Use body for details** - Explain what and why, not how
- **Reference issues** - Use "Closes #123" or "Fixes #123"
- **Separate subject and body** - Blank line between them

**Good Examples:**
- `fix(error_log): prevent duplicate error entries for same stack trace`
- `feat(dashboard): add filtering by platform and severity`
- `docs(readme): update installation instructions for Rails 8`

**Bad Examples:**
- `Fixed bug` (too vague)
- `WIP` (not descriptive)
- `asdf` (meaningless)

### Squashing Commits

Before submitting your PR, squash intermediate commits:

```bash
# Interactive rebase (last 3 commits)
git rebase -i HEAD~3

# Mark commits as 'squash' or 's' in the editor
# Edit the final commit message
# Force push to your branch
git push --force-with-lease origin feature/my-feature
```

## Documentation

Good documentation helps users understand and use your contributions.

### What to Document

**User-facing changes require documentation:**
- New features → README.md + guides in `docs/`
- Changed behavior → Update relevant docs
- New configuration options → docs/guides/CONFIGURATION.md
- Breaking changes → CHANGELOG.md with migration guide

**Code-level changes may need comments:**
- Complex algorithms → Explain the approach
- Non-obvious decisions → Explain why, not what
- Public APIs → RDoc comments

### Documentation Style

**README.md:**
- Keep it concise and scannable
- Use code examples
- Link to detailed guides in `docs/`

**Guides in docs/:**
- Use clear headings and table of contents
- Provide code examples
- Include troubleshooting section
- Add links to related guides

**Code comments (RDoc):**
```ruby
# Calculates baseline metrics for error rates
#
# @param error_type [String] The type of error to analyze
# @param platform [String] Optional platform filter
# @param days [Integer] Number of days of historical data (default: 30)
# @return [Hash] Statistical metrics (mean, stddev, percentiles)
#
# @example Calculate baseline for NoMethodError on iOS
#   BaselineCalculator.calculate(
#     error_type: "NoMethodError",
#     platform: "iOS",
#     days: 60
#   )
def calculate(error_type:, platform: nil, days: 30)
  # Implementation
end
```

### CHANGELOG Guidelines

All user-visible changes must be documented in CHANGELOG.md.

**Add your changes to the `[Unreleased]` section:**

```markdown
## [Unreleased]

### Added
- Discord notification support (#123) @yourusername

### Fixed
- Duplicate error entries for identical stack traces (#124) @yourusername
```

**Categories:**
- `Added` - New features
- `Changed` - Changes to existing functionality
- `Deprecated` - Soon-to-be removed features
- `Removed` - Removed features
- `Fixed` - Bug fixes
- `Security` - Security fixes

**No CHANGELOG entry needed for:**
- Documentation-only changes
- Test-only changes
- Internal refactoring (no user impact)
- CI/build configuration

## Questions?

- **Bug reports** - [Open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues/new/choose)
- **Feature requests** - [Open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues/new/choose)
- **Questions** - [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Security issues** - See [SECURITY.md](.github/SECURITY.md)

## Recognition

Contributors are recognized in:
- CHANGELOG.md (with GitHub username)
- GitHub contributors page
- Release notes (for significant contributions)

Thank you for contributing! 🎉
