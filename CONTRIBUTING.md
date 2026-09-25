# Contributing to Rails Error Dashboard

First off, thank you for considering contributing to Rails Error Dashboard! It's people like you that make this gem better for everyone.

Following these guidelines helps communicate that you respect the time of the developers managing and developing this open source project. In return, they should reciprocate that respect in addressing your issue, assessing changes, and helping you finalize your pull requests.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Improving a Translation](#improving-a-translation)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
- [Testing](#testing)
- [Code Style](#code-style)
- [Commit Messages](#commit-messages)
- [Documentation](#documentation)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to anjan.jagirdar+red@gmail.com.

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

**Note:** If you find a **security vulnerability**, do NOT open an issue. Please follow our [Security Policy](SECURITY.md) instead.

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

### Improving a Translation

**This is the easiest way to help, and the one we most need.**

RED's dashboard ships in eleven languages. French has been **reviewed by a
native speaker**; every one except English and French is machine-translated and
**has not been** — the maintainer reads only English. Structure and plural
rules are verified mechanically; wording, register and idiom are verified by
nobody.

If you read any of German, Spanish, Brazilian Portuguese, Japanese, Russian,
Ukrainian, Polish, Italian or Simplified Chinese, you can fix that:

- **Just report it** — [open a translation correction issue](.github/ISSUE_TEMPLATE/translation_report.yml).
  No Ruby, no PR, no need to find the key.
- **Or fix it yourself** — every string is one value in one YAML file under
  `config/locales/`. Change the value, run `bin/i18n-check`, open the PR.
- **Or take a whole language** — [each unreviewed locale has an open issue](https://github.com/AnjanJ/rails_error_dashboard/issues?q=is%3Aissue+is%3Aopen+label%3Atranslation%3Aneeds-review)
  tracking its review, labelled `good first issue`.

**A one-key PR is a perfectly good PR.** You are not expected to review a whole
file, and correcting a single wrong word is a real contribution.

Full details, including what is deliberately left in English and why:
[docs/guides/TRANSLATIONS.md](docs/guides/TRANSLATIONS.md#contributing-a-translation-fix)

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
   - Do **not** edit CHANGELOG.md or the version number — release-please writes both from
     your commit messages (see [CHANGELOG Guidelines](#changelog-guidelines))

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

7. **Ensure tests pass on other Rails versions** (optional — CI runs the full Ruby × Rails
   matrix on every pull request)
   ```bash
   rm -f Gemfile.lock   # gitignored; pinned to the last Rails you installed
   RAILS_VERSION=7.0 bundle install
   RAILS_VERSION=7.0 bundle exec rspec
   ```
   See [docs/development/TESTING.md](docs/development/TESTING.md) for the matrix.

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
- [ ] **Conventional PR title** - PRs are squash-merged, so the title becomes the commit on `main` that release-please turns into the changelog (see [Commit Messages](#commit-messages)). No CHANGELOG.md edit
- [ ] **One feature per PR** - Unrelated changes belong in separate PRs
- [ ] **Clean commit history** - Squash "WIP" or "fix typo" commits
- [ ] **Up-to-date with main** - Rebase on latest main branch

**Note:** The pre-commit hook (via Lefthook) runs RuboCop on your staged Ruby files, the spec files you staged, bundle audit and the chaos suite — see [Pre-commit Hooks](#pre-commit-hooks). To skip only the slow chaos stage: `LEFTHOOK_EXCLUDE=chaos-tests git commit -m "message"`. To skip all hooks temporarily: `LEFTHOOK=0 git commit -m "message"`

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

4. **Set up the test database** (the same command CI runs)
   ```bash
   cd spec/dummy
   RAILS_ENV=test bundle exec rake db:schema:load
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
# Run all tests (unit + integration + system)
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lib/rails_error_dashboard/commands/log_error_spec.rb

# Run specific test (by line number)
bundle exec rspec spec/lib/rails_error_dashboard/commands/log_error_spec.rb:42

# Run unit/integration tests only (no browser needed)
bundle exec rspec --exclude-pattern "spec/system/**/*"

# Run with the system specs' browser visible (for debugging)
HEADLESS=false bundle exec rspec

# Run with Chrome DevTools inspector
INSPECTOR=true HEADLESS=false bundle exec rspec
```

**A directory argument does not narrow the run.** `spec/spec_helper.rb` pins
`config.pattern` to every spec under `spec/`, so `bundle exec rspec spec/system/`
runs the whole suite, system specs included — CI's system-test job runs exactly
that and reports the full example count. Use `--exclude-pattern` (above) to leave
the browser specs out.

### System Tests

System tests use **Capybara + Cuprite** to automate real browser interactions (opening Bootstrap modals, filling forms, clicking buttons, verifying page content). They require Chrome or Chromium installed locally.

System test files live in `spec/system/`. Helper modules:
- `spec/support/system_helpers.rb` — Authentication and navigation helpers
- `spec/support/modal_helpers.rb` — Bootstrap modal interaction helpers
- `spec/support/capybara.rb` — Cuprite driver configuration

### Test Coverage

We use SimpleCov to track test coverage. It runs on every `bundle exec rspec`; open `coverage/index.html` in your browser afterwards to see the report. `ENFORCE_COVERAGE=true` also fails the run below 80%.

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

Lefthook runs the pre-commit hook in two stages (see `lefthook.yml`). Stage 2 runs only
if stage 1 passes.

**Stage 1 — fast checks on what you staged:**
- RuboCop on staged `.rb` files (it reports; it does not auto-correct)
- RSpec on staged `*_spec.rb` files
- Bundle audit (vulnerable dependencies)
- Debugger statement check
- `bin/i18n-check`, when a locale file is staged
- Trailing whitespace check

**Stage 2 — the pre-release chaos suite** (`bin/pre-release-test all`): builds four
temporary Rails apps in production mode. It takes several minutes.

There is no pre-push hook; CI runs the full suite on your pull request.

**To skip hooks temporarily:**
```bash
# Skip only the chaos stage (fast checks still run)
LEFTHOOK_EXCLUDE=chaos-tests git commit -m "message"

# Skip all hooks
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

Refs #123
```

**Your PR title is the commit message that counts.** PRs are squash-merged, and the
squashed commit takes the PR title as its subject. That subject is what release-please
reads to build the changelog, so give the PR a Conventional Commits title.

### Types

- `feat:` - New feature (listed in the changelog)
- `fix:` - Bug fix (listed in the changelog)
- `perf:` - Performance improvements (listed in the changelog)
- `docs:` - Documentation changes (hidden from the changelog)
- `refactor:` - Code refactoring, no feature change (hidden from the changelog)
- `test:` - Adding or updating tests (hidden from the changelog)
- `chore:` - Maintenance tasks such as dependencies or build (hidden from the changelog)
- `style:` - Code style changes (formatting, no logic change)
- `ci:` - CI/CD changes

### Guidelines

- **Use present tense** - "Add feature" not "Added feature"
- **Be concise** - 50 chars or less for subject line
- **Use body for details** - Explain what and why, not how
- **Reference issues with "Refs #123"** - Please avoid GitHub's closing keywords (Closes, Fixes, Resolves). They close the issue the moment the PR merges, and this project leaves an issue open until its reporter has confirmed the fix
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
- Breaking changes → describe them, with upgrade steps, in the PR description (CHANGELOG.md is generated; see below)

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

**Don't edit CHANGELOG.md, and don't bump the version.** Both are owned by
[release-please](https://github.com/googleapis/release-please), configured in
`.release-please-config.json`. When commits land on `main`, it opens (or updates) a
release PR that adds a changelog section and bumps
`lib/rails_error_dashboard/version.rb`; merging that PR publishes the gem.

The Conventional Commit type of the squashed commit (your PR title) decides where it
appears:

| Type | Changelog section |
|------|-------------------|
| `feat` | ✨ Features |
| `fix` | 🐛 Bug Fixes |
| `perf` | ⚡ Performance |
| `docs`, `test`, `refactor`, `chore` | Hidden — no entry |

The type also drives the version bump: `fix` gives a patch release, `feat` a minor one.
The maintainer can override the bump for a release.

If your change is breaking, or users need to do something when they upgrade, say so in
the PR description so it can be carried into the release notes.

## Questions?

- **Bug reports** - [Open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues/new/choose)
- **Feature requests** - [Open an issue](https://github.com/AnjanJ/rails_error_dashboard/issues/new/choose)
- **Questions** - [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)
- **Security issues** - See [SECURITY.md](SECURITY.md)

## Recognition

Contributors are recognized in:
- [CONTRIBUTORS.md](CONTRIBUTORS.md)
- GitHub contributors page
- Release notes (for significant contributions)

Thank you for contributing! 🎉
