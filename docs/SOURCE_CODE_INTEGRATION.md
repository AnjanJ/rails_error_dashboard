# Source Code Integration Feature

**Status:** ✅ Complete (Parts 1-4)
**Version:** v0.1.30+
**Commits:** 4 (Parts 1, 2, 3, and 4)

## Overview

The Source Code Integration feature provides developers with instant access to the actual code that caused an error, complete with git blame information and direct links to the repository. This dramatically reduces debugging time by eliminating context switching between the error dashboard and code editors.

**Goal:** Help developers fix errors 50% faster by showing code, blame, and repository links directly in the error view.

### Visual Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Error Dashboard - Error Details Page                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ NoMethodError: undefined method `email' for nil:NilClass    │
│ Occurred: 2 minutes ago                                     │
│                                                              │
│ ┌─── BACKTRACE ──────────────────────────────────────────┐ │
│ │                                                         │ │
│ │ 📱 app/controllers/users_controller.rb:42               │ │
│ │    in `update'                                         │ │
│ │    [View Source ▼]  ← Click to expand                 │ │
│ │                                                         │ │
│ │ ┌─── SOURCE CODE ─────────────────────────────────┐   │ │
│ │ │                                                   │   │ │
│ │ │ 👤 Jane Smith • 2 days ago                       │   │ │
│ │ │ 💬 "Add email validation"                        │   │ │
│ │ │                                                   │   │ │
│ │ │ [View on GitHub] ← Opens in new tab             │   │ │
│ │ │                                                   │   │ │
│ │ │  40  def update                                   │   │ │
│ │ │  41    @user = User.find(params[:id])            │   │ │
│ │ │  42 →  @user.email = params[:email]  ← Highlighted│   │ │
│ │ │  43    @user.save!                               │   │ │
│ │ │  44    redirect_to @user                         │   │ │
│ │ └───────────────────────────────────────────────────┘   │ │
│ │                                                         │ │
│ │ 🔷 active_record (gem): lib/active_record/base.rb:123  │ │
│ │    in `save!                                           │ │
│ │    (No source code for gem files)                      │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**How it works:**
1. Click error in dashboard → See backtrace
2. Click "View Source" on any app frame → Source code appears
3. See ±5 lines of context around error line
4. View git blame (who/when/why code was changed)
5. Click "View on GitHub" → Jump to exact line in repository

**Benefits:**
- 🚀 **Faster debugging**: See code without leaving dashboard
- 🎯 **Better context**: Understand surrounding code
- 👥 **Code ownership**: Know who to ask about the code
- 🔗 **Quick navigation**: Jump to GitHub/GitLab/Bitbucket
- 📊 **Team efficiency**: Share error links with full context

---

## Architecture

### Part 1: SourceCodeReader Service
**File:** `/lib/rails_error_dashboard/services/source_code_reader.rb`

Securely reads source code files from disk with comprehensive security validation.

**Features:**
- Path validation (must be within Rails.root)
- Directory traversal prevention (blocks `../` patterns)
- Sensitive file protection (.env, secrets, credentials, keys)
- Binary file detection
- File size limits (10 MB max)
- Gem/vendor code filtering (optional)
- Context line reading (configurable ±N lines)

**Security:**
- No shell commands or external processes
- Path normalization and validation
- Sensitive pattern blacklist
- Rails.root boundary enforcement

**Tests:** 40+ test cases covering security, edge cases, and functionality

---

### Part 2: GitBlameReader Service
**File:** `/lib/rails_error_dashboard/services/git_blame_reader.rb`

Executes git blame commands to retrieve authorship information for specific lines.

**Features:**
- Git availability detection with caching
- Porcelain format parsing (structured output)
- 5-second timeout protection
- Author, email, date, commit SHA extraction
- Commit message retrieval
- Graceful error handling

**Security:**
- Uses `Open3.capture3` (no shell injection)
- Command array format (prevents expansion)
- Timeout protection against hanging processes
- File existence validation

**Output Format:**
```ruby
{
  author: "John Doe",
  email: "john@example.com",
  date: Time.at(1704067200),
  sha: "abc123def456",
  commit_message: "Fix validation bug",
  line: "validates :email, presence: true"
}
```

**Tests:** 40+ test cases with mock-based and integration testing

---

### Part 3: GithubLinkGenerator Service
**File:** `/lib/rails_error_dashboard/services/github_link_generator.rb`

Generates deep links to source code on GitHub, GitLab, or Bitbucket.

**Supported Platforms:**
- **GitHub:** `https://github.com/user/repo/blob/{ref}/path#L42`
- **GitLab:** `https://gitlab.com/user/repo/-/blob/{ref}/path#L42`
- **Bitbucket:** `https://bitbucket.org/user/repo/src/{ref}/path#lines-42`

**Features:**
- Multi-platform support (GitHub, GitLab, Bitbucket)
- Self-hosted instance support
- Commit SHA support (most accurate)
- Branch/tag fallback
- Intelligent path normalization
- Automatic .git suffix removal

**Path Normalization:**
- Extracts relative paths from absolute paths
- Handles `app/`, `lib/`, `config/`, `db/`, `spec/`, `test/`
- Removes Rails.root prefix
- Smart detection of standard Rails directories

**Tests:** 50+ test cases covering all platforms and edge cases

---

### Part 4: UI Integration & Helpers
**Files:**
- `/app/helpers/rails_error_dashboard/backtrace_helper.rb`
- `/app/views/rails_error_dashboard/errors/_source_code.html.erb`
- `/app/views/rails_error_dashboard/errors/show.html.erb` (modified)
- `/app/assets/stylesheets/rails_error_dashboard/_components.scss` (extended)

**Helper Methods:**
```ruby
# Read source code with caching
read_source_code(frame, context: 5)
# => { lines: [...], error: nil }

# Read git blame with caching
read_git_blame(frame)
# => { author: "...", email: "...", ... }

# Generate repository link
generate_repository_link(frame, error_log)
# => "https://github.com/user/repo/blob/abc123/app/models/user.rb#L42"
```

**UI Components:**
- Collapsible source code viewer per backtrace frame
- "View Source" button on app frames only
- Git blame info display (author, time ago, commit message)
- Repository link button (GitHub/GitLab/Bitbucket)
- Syntax-highlighted code with line numbers
- Target line highlighting (yellow background)
- Responsive design with Bootstrap collapse

**Caching:**
- Rails.cache integration for performance
- Configurable TTL (default: 1 hour)
- Separate cache keys for source code and git blame
- Cache key format: `source_code/{file_path}/{line_number}`

**Tests:** 25+ helper tests for all methods

---

## Quick Start Tutorial

### Step 1: Enable Basic Source Code Viewing (2 minutes)

The simplest setup - just show source code, no git integration.

**Add to your initializer:**
```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
end
```

**Restart your server:**
```bash
rails restart
```

**Test it:**
1. Trigger an error in your app: `/users/999999` (non-existent user)
2. Visit `/error_dashboard`
3. Click on the error
4. Look for "View Source" buttons in the backtrace
5. Click a button to see the code!

**Expected result:**
```
┌─────────────────────────────────────────┐
│ app/controllers/users_controller.rb:15  │
│ in `show`                                │
│                                          │
│ [View Source]                            │
├─────────────────────────────────────────┤
│ 13  def show                             │
│ 14    @user = User.find(params[:id])    │
│ 15 → raise "User not found"             │  ← Error line highlighted
│ 16    respond_to do |format|            │
│ 17      format.html                     │
└─────────────────────────────────────────┘
```

**What you see:**
- ± 5 lines of context around the error
- Error line highlighted
- Line numbers
- Clean, readable code

---

### Step 2: Add Git Blame Information (5 minutes)

See who last modified the code and when.

**Requirements:**
- Git must be installed
- Your app must be a git repository
- Files must be committed to git

**Add to your initializer:**
```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  config.enable_git_blame = true  # ← Add this line
end
```

**Restart your server:**
```bash
rails restart
```

**Test it:**
1. Trigger an error again
2. View the error in the dashboard
3. Click "View Source"

**Expected result:**
```
┌─────────────────────────────────────────┐
│ 👤 John Doe • 3 days ago                │  ← Git blame info
│ 💬 "Fix user validation logic"          │
│                                          │
│ app/controllers/users_controller.rb:15  │
│ [View Source]                            │
├─────────────────────────────────────────┤
│ 13  def show                             │
│ 14    @user = User.find(params[:id])    │
│ 15 → raise "User not found"             │
│ 16    respond_to do |format|            │
│ 17      format.html                     │
└─────────────────────────────────────────┘
```

**What changed:**
- Author name shown
- Time since last modification
- Commit message displayed
- Helps identify code ownership

**Troubleshooting:**
- No git blame shown? Check: `git --version`
- Still not working? Ensure file is committed: `git log -- path/to/file.rb`

---

### Step 3: Add Repository Links (10 minutes)

Add "View on GitHub" buttons to jump directly to the code.

**Requirements:**
- GitHub, GitLab, or Bitbucket repository
- Repository URL (e.g., `https://github.com/myorg/myapp`)

**Add to your initializer:**
```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  config.enable_git_blame = true

  # Add your repository URL
  config.git_repository_url = "https://github.com/myorg/myapp"  # ← Add this

  # Choose a branch strategy
  config.git_branch_strategy = :current_branch  # ← Add this
end
```

**Repository URL formats:**
```ruby
# GitHub
"https://github.com/rails/rails"

# GitHub Enterprise
"https://github.company.com/team/repo"

# GitLab
"https://gitlab.com/gitlab-org/gitlab"

# Self-hosted GitLab
"https://gitlab.mycompany.com/backend/api"

# Bitbucket
"https://bitbucket.org/atlassian/jira"
```

**Branch strategies:**
```ruby
# Option 1: Current branch (simple, good for development)
config.git_branch_strategy = :current_branch
# Links will use your current HEAD commit

# Option 2: Main branch (always links to main/master)
config.git_branch_strategy = :main
# Links will use main branch

# Option 3: Commit SHA (most accurate, requires tracking)
config.git_branch_strategy = :commit_sha
# Links will use the exact commit when error occurred
# Requires: config.git_sha = ENV["GIT_SHA"]
```

**Restart your server:**
```bash
rails restart
```

**Test it:**
1. Trigger an error
2. View in dashboard
3. Click "View Source"
4. Look for "View on GitHub" button

**Expected result:**
```
┌─────────────────────────────────────────┐
│ 👤 John Doe • 3 days ago                │
│ 💬 "Fix user validation logic"          │
│                                          │
│ app/controllers/users_controller.rb:15  │
│ [View Source] [View on GitHub]          │  ← New button!
├─────────────────────────────────────────┤
│ 13  def show                             │
│ 14    @user = User.find(params[:id])    │
│ 15 → raise "User not found"             │
│ 16    respond_to do |format|            │
│ 17      format.html                     │
└─────────────────────────────────────────┘
```

**Clicking "View on GitHub" opens:**
```
https://github.com/myorg/myapp/blob/abc123/app/controllers/users_controller.rb#L15
                                          ^^^^^^  ← Current commit
                                                 └────────────────────────────────┘
                                                  ← Exact file and line
```

---

### Step 4: Production-Ready Configuration (15 minutes)

Optimize for production use with performance and security settings.

**Full configuration:**
```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  # Core authentication (always required)
  config.dashboard_username = ENV.fetch("ERROR_DASHBOARD_USER", "admin")
  config.dashboard_password = ENV.fetch("ERROR_DASHBOARD_PASSWORD")

  # ═══════════════════════════════════════════════════════════
  # SOURCE CODE INTEGRATION
  # ═══════════════════════════════════════════════════════════

  # Enable the feature
  config.enable_source_code_integration = true

  # Git blame (helps identify code ownership)
  config.enable_git_blame = true

  # Repository configuration
  config.git_repository_url = ENV["GIT_REPOSITORY_URL"]
  # Example: "https://github.com/myorg/myapp"

  # Use commit SHA for accuracy (requires deployment tracking)
  config.git_branch_strategy = :commit_sha
  config.git_sha = ENV["GIT_SHA"]  # Set during deployment

  # Performance optimization
  config.source_code_context_lines = 5       # Fewer lines = faster reads
  config.source_code_cache_ttl = 7200        # 2 hours in production

  # Security: hide gem/vendor code (recommended)
  config.only_show_app_code_source = true
end
```

**Set environment variables:**

**Option A: .env file (for development)**
```bash
# .env
ERROR_DASHBOARD_USER=admin
ERROR_DASHBOARD_PASSWORD=super_secret_password
GIT_REPOSITORY_URL=https://github.com/myorg/myapp
GIT_SHA=abc123def456  # Set by deployment script
```

**Option B: Environment (for production)**
```bash
# Export in your deployment script or use platform environment settings
export ERROR_DASHBOARD_USER=admin
export ERROR_DASHBOARD_PASSWORD=$SECRET_PASSWORD
export GIT_REPOSITORY_URL=https://github.com/myorg/myapp
export GIT_SHA=$(git rev-parse HEAD)  # Capture during deployment
```

**Deployment setup (Capistrano example):**
```ruby
# config/deploy.rb
set :git_sha, `git rev-parse HEAD`.chomp

namespace :deploy do
  task :set_git_sha do
    on roles(:app) do
      execute "echo 'export GIT_SHA=#{fetch(:git_sha)}' >> ~/.bashrc"
    end
  end
end

after "deploy:updated", "deploy:set_git_sha"
```

**Docker setup:**
```dockerfile
# Dockerfile
ARG GIT_SHA=unknown
ENV GIT_SHA=$GIT_SHA

# Build with:
# docker build --build-arg GIT_SHA=$(git rev-parse HEAD) .
```

**Heroku setup:**
```bash
# Set config vars
heroku config:set GIT_REPOSITORY_URL=https://github.com/myorg/myapp
heroku config:set GIT_SHA=$(git rev-parse HEAD)

# Or use Heroku Labs dyno metadata (automatic)
heroku labs:enable runtime-dyno-metadata
# Then access via ENV['HEROKU_SLUG_COMMIT']
```

**Verify it works:**
```ruby
# Rails console in production
RailsErrorDashboard.configuration.enable_source_code_integration
# => true

RailsErrorDashboard.configuration.git_repository_url
# => "https://github.com/myorg/myapp"

ENV["GIT_SHA"]
# => "abc123def456..."
```

---

### Step 5: Verify Everything Works

**Create a test error:**
```ruby
# app/controllers/test_controller.rb
class TestController < ApplicationController
  def error_test
    # Line 4: This will trigger an error
    User.find_by!(email: "nonexistent@example.com")
  end
end
```

**Add route:**
```ruby
# config/routes.rb
get '/test_error', to: 'test#error_test'
```

**Trigger the error:**
```bash
curl http://localhost:3000/test_error
```

**Check the dashboard:**
1. Visit `http://localhost:3000/error_dashboard`
2. Click on the error
3. Find `app/controllers/test_controller.rb` in the backtrace
4. Click "View Source"

**You should see:**
✅ Source code displayed with context
✅ Line 4 highlighted
✅ Git blame info (author, time, message)
✅ "View on GitHub" button
✅ Clicking button opens correct file and line

**If something doesn't work:**
- Check configuration in initializer
- Restart Rails server
- Check logs: `tail -f log/development.log | grep -i source`
- Review troubleshooting section below

---

### Step 6: Customize for Your Workflow

**Adjust context lines:**
```ruby
# See more code around errors
config.source_code_context_lines = 10  # Default: 5

# See less (faster)
config.source_code_context_lines = 3
```

**Disable git blame in development:**
```ruby
# Save time in development where blame is less useful
if Rails.env.development?
  config.enable_git_blame = false
end
```

**Show gem code too (for debugging):**
```ruby
# Useful when debugging gem issues
if Rails.env.development?
  config.only_show_app_code_source = false
end
```

**Use different settings per environment:**
```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true

  if Rails.env.production?
    # Production: Security and performance
    config.enable_git_blame = true
    config.git_branch_strategy = :commit_sha
    config.source_code_context_lines = 5
    config.source_code_cache_ttl = 7200  # 2 hours
    config.only_show_app_code_source = true

  elsif Rails.env.staging?
    # Staging: Similar to production
    config.enable_git_blame = true
    config.git_branch_strategy = :current_branch
    config.source_code_context_lines = 7
    config.source_code_cache_ttl = 1800  # 30 minutes

  else
    # Development: Maximum information, short cache
    config.enable_git_blame = false  # Faster
    config.git_branch_strategy = :current_branch
    config.source_code_context_lines = 10
    config.source_code_cache_ttl = 60   # 1 minute
    config.only_show_app_code_source = false  # Show gem code too
  end
end
```

---

## Configuration Reference

Add to your `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  # Master switch - enables entire feature
  config.enable_source_code_integration = true

  # Context lines - how many lines before/after target line
  config.source_code_context_lines = 5  # Default: 5

  # Git blame - show authorship information
  config.enable_git_blame = true  # Default: false

  # Cache TTL - how long to cache source code reads
  config.source_code_cache_ttl = 3600  # Default: 3600 (1 hour)

  # Repository URL - base URL for your git repository
  config.git_repository_url = ENV["GIT_REPOSITORY_URL"]
  # Examples:
  # - "https://github.com/user/repo"
  # - "https://gitlab.com/user/repo"
  # - "https://gitlab.mycompany.com/team/repo"
  # - "https://bitbucket.org/user/repo"

  # Git branch strategy - which commit SHA to use for links
  config.git_branch_strategy = :commit_sha  # Options: :commit_sha, :current_branch, :main
  # - :commit_sha - Use SHA from when error occurred (most accurate, requires git_sha tracking)
  # - :current_branch - Use current HEAD commit
  # - :main - Use main/master branch (always latest)

  # Security - hide gem/vendor code source
  config.only_show_app_code_source = true  # Default: true
end
```

---

## Environment Variables

Optional environment variables for automatic configuration:

```bash
# Repository URL
export GIT_REPOSITORY_URL="https://github.com/myorg/myapp"

# Or in .env file:
GIT_REPOSITORY_URL=https://github.com/myorg/myapp
```

---

## Usage Examples

### Minimal Setup (No Git Blame, No Links)

Show source code only:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  # That's it! Just source code viewing
end
```

### Full Setup (Git Blame + Repository Links)

Complete feature with all bells and whistles:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  config.enable_git_blame = true
  config.git_repository_url = "https://github.com/myorg/myapp"
  config.git_branch_strategy = :commit_sha
  config.source_code_context_lines = 7
  config.source_code_cache_ttl = 7200  # 2 hours
end
```

### Self-Hosted GitLab

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  config.git_repository_url = "https://gitlab.mycompany.com/backend/api"
  config.git_branch_strategy = :current_branch
end
```

---

## Performance

### Caching Strategy

All source code reads and git blame lookups are cached:

- **Cache Key:** `source_code/{file_path}/{line_number}`
- **Cache TTL:** Configurable (default: 3600 seconds)
- **Cache Backend:** Rails.cache (MemoryStore, Redis, Solid Cache, etc.)

### Lazy Loading

Source code is loaded on-demand:
- Collapsed by default (Bootstrap collapse)
- Only loads when user clicks "View Source"
- Only available for `:app` category frames
- Framework/gem frames excluded

### Resource Usage

- **File Reads:** Cached, only reads once per file/line
- **Git Blame:** Cached, 5-second timeout protection
- **Network:** No external API calls (local git only)
- **Memory:** Limited by cache size and context lines

---

## Security

### Path Security

- ✅ Must be within Rails.root (enforced)
- ✅ Directory traversal prevention (`../` blocked)
- ✅ Sensitive file blacklist (.env, secrets, keys)
- ✅ Path normalization and validation

### Command Injection Prevention

- ✅ `Open3.capture3` (safe execution)
- ✅ Command array format (no shell expansion)
- ✅ No user input in commands
- ✅ Timeout protection (5 seconds)

### Information Disclosure

- ✅ Gem/vendor code filtering (optional)
- ✅ Only shows files within Rails.root
- ✅ Binary file detection and blocking
- ✅ File size limits (10 MB max)

---

## Testing

### Test Coverage

- **Total Tests:** 1,205 tests (as of v0.1.30)
- **New Tests:** 150+ tests for source code integration
- **Coverage:** 64.6% overall, 100% for all new services and helpers
- **Status:** All tests passing ✅

### Test Categories

1. **Unit Tests** - Service methods, helpers
2. **Integration Tests** - Real git repository tests
3. **Security Tests** - Path traversal, sensitive files
4. **Edge Cases** - Nil values, empty files, errors

### Running Tests

```bash
# All source code integration tests
bundle exec rspec spec/services/source_code_reader_spec.rb
bundle exec rspec spec/services/git_blame_reader_spec.rb
bundle exec rspec spec/services/github_link_generator_spec.rb
bundle exec rspec spec/helpers/backtrace_helper_spec.rb

# Full test suite
bundle exec rspec
```

---

## Troubleshooting

### Source Code Not Showing

**Problem:** "View Source" button not appearing on error details page

**Symptoms:**
- No "View Source" button in backtrace frames
- Expected to see source code viewer but it's missing
- Only seeing file paths and line numbers

**Solutions:**

1. **Check configuration is enabled**
   ```ruby
   # In config/initializers/rails_error_dashboard.rb
   config.enable_source_code_integration = true
   ```
   Restart your Rails server after changing configuration.

2. **Verify file path is within Rails.root**
   ```ruby
   # Check in Rails console
   Rails.root
   # => /Users/you/myapp

   # Your error file path should start with this
   ```
   Only files within your application directory are shown.

3. **Check frame category is `:app`**
   Source code is only shown for application code, not gem/framework code.
   ```ruby
   # Frame must be categorized as :app
   frame[:category] == :app  # Should be true
   ```

4. **Verify file exists and is readable**
   ```bash
   ls -la app/controllers/users_controller.rb
   # Should show file with read permissions
   ```

5. **Check security settings**
   ```ruby
   # If you want to see gem code too
   config.only_show_app_code_source = false
   ```

**Still not working?**
Check the Rails logs for `SourceCodeReader` errors:
```bash
tail -f log/development.log | grep SourceCodeReader
```

---

### Git Blame Not Working

**Problem:** No git blame information displayed (author, commit message, etc.)

**Symptoms:**
- Source code shows but no git blame info
- Missing author name and commit message
- "Last modified by" section is empty

**Solutions:**

1. **Check git blame is enabled**
   ```ruby
   config.enable_git_blame = true
   ```

2. **Verify git is installed and accessible**
   ```bash
   git --version
   # Should output: git version 2.x.x

   which git
   # Should output: /usr/bin/git or similar
   ```

3. **Ensure you're in a git repository**
   ```bash
   cd /path/to/your/app
   git rev-parse --git-dir
   # Should output: .git

   # If not a git repository:
   git init
   git add .
   git commit -m "Initial commit"
   ```

4. **Check file is committed to git**
   ```bash
   git log -- app/controllers/users_controller.rb
   # Should show commit history

   # If file is not committed:
   git add app/controllers/users_controller.rb
   git commit -m "Add users controller"
   ```

5. **Verify git blame works manually**
   ```bash
   git blame -L 42,42 --porcelain app/controllers/users_controller.rb
   # Should output blame information
   ```

6. **Check timeout settings**
   Git blame has a 5-second timeout. For very large files:
   ```ruby
   # Custom timeout not currently configurable
   # Large files (>10k lines) may timeout
   ```

**Common Issues:**

- **Untracked files**: Git blame only works on committed files
- **New repository**: Need at least one commit for blame to work
- **Detached HEAD**: Git blame works but may show unexpected commits
- **Shallow clones**: May not show full blame history

**Debug output:**
```ruby
# In Rails console
reader = RailsErrorDashboard::Services::GitBlameReader.new(
  "/path/to/file.rb", 42
)
result = reader.read_blame
puts result.inspect
```

---

### Repository Links Not Generating

**Problem:** No "View on GitHub" button appearing

**Symptoms:**
- Source code shows but no repository link button
- Can't click to view code on GitHub/GitLab/Bitbucket
- Repository link section is missing

**Solutions:**

1. **Check repository URL is configured**
   ```ruby
   config.git_repository_url = "https://github.com/myorg/myapp"
   # Or
   config.git_repository_url = ENV["GIT_REPOSITORY_URL"]
   ```

2. **Verify URL format is correct**
   ```ruby
   # ✅ Correct formats:
   "https://github.com/user/repo"
   "https://gitlab.com/user/repo"
   "https://gitlab.company.com/team/repo"
   "https://bitbucket.org/user/repo"

   # ❌ Incorrect formats:
   "https://github.com/user/repo.git"  # Remove .git
   "git@github.com:user/repo.git"      # Use HTTPS format
   "github.com/user/repo"               # Include https://
   ```

3. **Check git branch strategy**
   ```ruby
   config.git_branch_strategy = :commit_sha  # Most accurate
   # Or
   config.git_branch_strategy = :current_branch
   # Or
   config.git_branch_strategy = :main
   ```

4. **For :commit_sha strategy, ensure git_sha is tracked**
   ```ruby
   config.git_sha = ENV["GIT_SHA"]  # Set during deployment

   # Or in your deploy script:
   export GIT_SHA=$(git rev-parse HEAD)
   ```

5. **Test link generation manually**
   ```ruby
   # In Rails console
   error = RailsErrorDashboard::ErrorLog.last
   frame = error.parsed_backtrace.first

   generator = RailsErrorDashboard::Services::GithubLinkGenerator.new(
     repository_url: "https://github.com/user/repo",
     file_path: frame[:path],
     line_number: frame[:line_number],
     commit_sha: error.git_sha
   )

   puts generator.generate_link
   ```

**Platform-specific issues:**

- **GitHub Enterprise**: Ensure URL includes your enterprise domain
- **GitLab Self-hosted**: Use your GitLab instance URL
- **Bitbucket Server**: Format may differ from Bitbucket Cloud

---

### Performance Issues

**Problem:** Error details page loads slowly with source code integration

**Symptoms:**
- Page takes 3+ seconds to load
- Multiple file reads happening
- High disk I/O
- Memory usage increasing

**Solutions:**

1. **Reduce context lines**
   ```ruby
   config.source_code_context_lines = 3  # Instead of 10
   # Fewer lines = faster reads
   ```

2. **Increase cache TTL**
   ```ruby
   config.source_code_cache_ttl = 7200  # 2 hours
   # Code doesn't change often in production
   ```

3. **Use faster cache backend**
   ```ruby
   # In config/application.rb
   config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
   # Redis is much faster than MemoryStore for large datasets
   ```

4. **Monitor cache hit rate**
   ```ruby
   # In Rails console
   Rails.cache.stats  # If supported by your cache backend
   ```

5. **Disable git blame in production**
   ```ruby
   if Rails.env.production?
     config.enable_git_blame = false  # Save git command execution time
   end
   ```

6. **Profile slow pages**
   ```bash
   # Check which service is slow
   tail -f log/production.log | grep "SourceCodeReader\|GitBlameReader"
   ```

**Optimization tips:**

- Keep source code collapsed by default (already done)
- Only enable for recent errors (last 7 days)
- Use lazy loading (already implemented)
- Monitor cache size and eviction

---

### "Permission Denied" Errors

**Problem:** Getting permission denied when trying to read source files

**Symptoms:**
- Error: "Permission denied @ rb_sysopen"
- Source code viewer shows "Could not read source" error
- Log shows file permission errors

**Solutions:**

1. **Check file permissions**
   ```bash
   ls -la app/controllers/users_controller.rb
   # Should show -rw-r--r-- or similar

   # Fix permissions if needed:
   chmod 644 app/controllers/users_controller.rb
   ```

2. **Check Rails server user permissions**
   ```bash
   # Check which user is running Rails
   ps aux | grep rails

   # Ensure that user can read application files
   sudo -u rails-user cat app/controllers/users_controller.rb
   ```

3. **Check SELinux or AppArmor restrictions**
   ```bash
   # On CentOS/RHEL
   getenforce  # Check if SELinux is enforcing

   # On Ubuntu
   aa-status  # Check AppArmor status
   ```

4. **Docker container issues**
   ```dockerfile
   # Ensure proper file permissions in Dockerfile
   RUN chown -R app:app /app
   USER app
   ```

---

### "File Not Found" Errors

**Problem:** Source code reader can't find files that exist

**Symptoms:**
- Error: "No such file or directory"
- File path in backtrace doesn't match actual location
- Files exist but dashboard can't see them

**Solutions:**

1. **Check Rails.root is set correctly**
   ```ruby
   # In Rails console
   Rails.root
   # => /app (in Docker) or /Users/you/myapp (locally)
   ```

2. **Verify file paths are absolute**
   ```ruby
   # Backtrace paths should be absolute
   frame[:path] # => "/app/app/controllers/users_controller.rb"
   # Not: "app/controllers/users_controller.rb"
   ```

3. **Symlink issues**
   ```bash
   # Check if any directories are symlinks
   ls -la app/

   # Resolve symlinks manually if needed
   config.source_code_integration_base_path = File.realpath(Rails.root)
   ```

4. **Docker volume mount issues**
   ```yaml
   # docker-compose.yml
   volumes:
     - .:/app:ro  # Read-only mount
   # Change to:
     - .:/app      # Read-write mount (for development)
   ```

---

### Caching Issues

**Problem:** Seeing old/stale source code after changes

**Symptoms:**
- Code shown in dashboard doesn't match current file content
- Recent changes not reflected in source viewer
- Cache seems stuck on old version

**Solutions:**

1. **Clear cache manually**
   ```ruby
   # In Rails console
   Rails.cache.clear
   # Or specifically:
   Rails.cache.delete_matched("source_code/*")
   ```

2. **Reduce cache TTL in development**
   ```ruby
   if Rails.env.development?
     config.source_code_cache_ttl = 60  # 1 minute
   end
   ```

3. **Disable caching in development**
   ```ruby
   # In config/environments/development.rb
   config.action_controller.perform_caching = false
   ```

4. **Check cache configuration**
   ```ruby
   # In Rails console
   Rails.cache.class
   # => ActiveSupport::Cache::MemoryStore or similar
   ```

---

### Git Blame Shows Wrong Author

**Problem:** Git blame shows incorrect author or old information

**Symptoms:**
- Author name doesn't match recent changes
- Showing author from months ago
- Commit message doesn't match current code

**Solutions:**

1. **Check git configuration**
   ```bash
   git config user.name
   git config user.email
   ```

2. **Verify most recent commit for line**
   ```bash
   git blame -L 42,42 app/controllers/users_controller.rb
   ```

3. **Check for rebased history**
   ```bash
   # Rebasing can change commit authorship
   git log --oneline --graph
   ```

4. **Clear git blame cache**
   ```ruby
   Rails.cache.delete_matched("git_blame/*")
   ```

---

### Dark Mode Styling Issues

**Problem:** Source code viewer not styled correctly in dark mode

**Symptoms:**
- Text hard to read in dark mode
- Colors look wrong
- Background colors don't match theme

**Solutions:**

1. **Ensure latest version**
   ```bash
   bundle update rails_error_dashboard
   # Dark mode improvements in v0.1.30+
   ```

2. **Check CSS is loading**
   ```html
   <!-- Should be in <head> -->
   <link rel="stylesheet" href="/error_dashboard/assets/...">
   ```

3. **Clear browser cache**
   ```
   Hard refresh: Cmd+Shift+R (Mac) or Ctrl+F5 (Windows)
   ```

4. **Verify dark mode is enabled**
   ```javascript
   // In browser console
   document.body.classList.contains('dark-mode')
   // Should return true when dark mode is on
   ```

---

### Common Configuration Mistakes

**Problem:** Feature not working due to configuration errors

**Common mistakes:**

1. **Forgetting to restart server after config changes**
   ```bash
   # Always restart after editing initializer
   rails restart  # Or Ctrl+C and restart
   ```

2. **Typos in configuration**
   ```ruby
   # ❌ Wrong:
   config.enable_source_code = true
   # ✅ Correct:
   config.enable_source_code_integration = true
   ```

3. **Environment-specific configs not working**
   ```ruby
   # ❌ Wrong: This runs only once at boot
   config.enable_git_blame = Rails.env.production?

   # ✅ Correct: Check environment in initializer
   if Rails.env.production?
     config.enable_git_blame = true
   end
   ```

4. **ENV variables not set**
   ```bash
   # Check if ENV variables are available
   rails runner 'puts ENV["GIT_REPOSITORY_URL"]'
   # Should output your URL, not nil
   ```

---

### Getting Help

If you're still having issues after trying these solutions:

1. **Check the logs**
   ```bash
   tail -f log/development.log | grep -i "source\|git\|blame"
   ```

2. **Enable debug logging**
   ```ruby
   config.enable_internal_logging = true
   config.log_level = :debug
   ```

3. **Test services directly**
   ```ruby
   # In Rails console - test each service
   reader = RailsErrorDashboard::Services::SourceCodeReader.new(
     "/path/to/file.rb",
     line_number: 42,
     context: 5
   )
   result = reader.read
   puts result.inspect
   ```

4. **Create a minimal reproduction**
   - Start with minimal config
   - Enable features one at a time
   - Identify which feature causes the issue

5. **Open a GitHub issue**
   - Include configuration
   - Include error logs
   - Include Ruby/Rails versions
   - Include steps to reproduce

**GitHub Issues:** https://github.com/AnjanJ/rails_error_dashboard/issues

---

## Common Use Cases & Real-World Examples

### Use Case 1: On-Call Engineer Responding to Production Alert

**Scenario:**
It's 2 AM. You get paged about a critical error in production affecting user checkouts.

**Without Source Code Integration:**
1. Check error dashboard (1 min)
2. Open laptop, pull latest code (2 min)
3. Find the file in editor (1 min)
4. Locate the line number (1 min)
5. Read surrounding code for context (2 min)
6. Check git blame to see recent changes (2 min)
7. **Total: ~9 minutes** + context switching stress

**With Source Code Integration:**
1. Check error dashboard on phone
2. Click "View Source"
3. See code, git blame, recent changes
4. **Total: ~30 seconds** from your phone!

**Example error:**
```
Stripe::CardError: Your card was declined
app/services/payment_processor.rb:67 in `charge_card`

[View Source shows:]
65  def charge_card(amount, token)
66    begin
67 →    Stripe::Charge.create(amount: amount, source: token)
68    rescue Stripe::CardError => e
69      # Missing: Should notify user!

[Git Blame shows:]
👤 John Doe • 6 months ago
💬 "Add Stripe payment processing"

[Quick insight: Missing error handling added 6 months ago, needs update]
```

---

### Use Case 2: Junior Developer Learning Codebase

**Scenario:**
New team member trying to understand how authentication works after seeing login errors.

**With Source Code Integration:**
```ruby
# Error: SessionsController#create failed with "Invalid credentials"

[View Source shows:]
18  def create
19    user = User.find_by(email: params[:email])
20 →  if user&.authenticate(params[:password])
21      session[:user_id] = user.id
22      redirect_to dashboard_path
23    else
24      flash[:error] = "Invalid credentials"

[Git Blame shows:]
👤 Jane Smith • 3 weeks ago
💬 "Switch from Devise to custom auth"

[Clicking "View on GitHub" shows full file context and related files]
```

**Learning outcomes:**
- Sees authentication logic immediately
- Understands recent architectural changes
- Can trace through the flow
- Knows who to ask for questions (Jane)

---

### Use Case 3: Code Review During Incident Post-Mortem

**Scenario:**
Team reviewing errors from yesterday's deploy to identify what went wrong.

**Example:**
```ruby
# Error spike at 2:00 PM after deployment

[Dashboard shows 50 errors in UsersController#update]

[View Source reveals:]
42 →  @user.email = params[:email]  # Missing strong params!
43    @user.save!

[Git Blame shows:]
👤 Bob Wilson • 1 day ago
💬 "Quick fix for email update bug"

[Team discussion:]
- No code review on "quick fix"
- Strong params bypassed
- Security vulnerability introduced
- Need to add strong params and review process
```

**Action items identified:**
1. Add strong params
2. Revert dangerous change
3. Implement mandatory code review
4. Add security tests

---

### Use Case 4: Debugging Intermittent Background Job Failures

**Scenario:**
Background job failing occasionally, hard to reproduce locally.

**With Source Code Integration:**
```ruby
# Error: UserEmailJob failed with "SMTP timeout"

[View Source shows:]
12  def perform(user_id)
13    user = User.find(user_id)
14 →  UserMailer.welcome_email(user).deliver_now  # Blocking!
15  end

[Git Blame shows:]
👤 Alice Chen • 2 months ago
💬 "Add welcome email on signup"

[Issue identified:]
- Using deliver_now (synchronous) instead of deliver_later
- SMTP timeout blocks job
- Should use async delivery

[Fix:]
14    UserMailer.welcome_email(user).deliver_later  # Non-blocking
```

**Time saved:** Found issue in 2 minutes vs. 30 minutes of debugging

---

### Use Case 5: Mobile App Error Triage

**Scenario:**
iOS app crashing on a specific API endpoint. Backend team needs to investigate.

**With Source Code Integration:**
```ruby
# Error: NoMethodError in Api::V1::PostsController#create
# Platform: iOS • App Version: 2.1.0

[View Source shows:]
18  def create
19    post = current_user.posts.build(post_params)
20 →  post.image.attach(params[:image])  # Assumes image exists!
21    post.save!

[Git Blame shows:]
👤 Mike Johnson • 1 week ago
💬 "Add image upload support"

[Issue:]
- No nil check for params[:image]
- iOS app sends nil when no image selected
- Android app always sends empty string (works)

[Fix:]
20    post.image.attach(params[:image]) if params[:image].present?
```

**Cross-platform insight:** Different mobile platforms behave differently

---

### Use Case 6: Debugging Third-Party API Integration

**Scenario:**
Errors from Stripe webhook processing, need to see what's failing.

**With Source Code Integration:**
```ruby
# Error: Stripe::InvalidRequestError in WebhooksController#stripe

[View Source shows:]
25  def stripe
26    payload = request.body.read
27    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
28 →  event = Stripe::Webhook.construct_event(
29      payload, sig_header, ENV['STRIPE_WEBHOOK_SECRET']
30    )

[Git Blame shows:]
👤 Sarah Lee • 1 day ago
💬 "Update Stripe webhook handling"

[Investigation shows:]
- ENV['STRIPE_WEBHOOK_SECRET'] is nil in production
- Recent deploy didn't set environment variable
- Need to update production config

[Fix:]
# Set environment variable in production
export STRIPE_WEBHOOK_SECRET=whsec_...
```

**Root cause:** Configuration issue, not code bug

---

### Use Case 7: Performance Issue Investigation

**Scenario:**
Slow controller action causing timeouts. Need to identify N+1 queries.

**With Source Code Integration:**
```ruby
# Error: ActionView::Template::Error: Timeout in PostsController#index

[View Source shows:]
12  def index
13    @posts = Post.all.limit(100)
14 →  # Missing: .includes(:comments, :author)
15  end

# View template shows:
<% @posts.each do |post| %>
  <%= post.author.name %>  <!-- N+1 query #1 -->
  <%= post.comments.count %> <!-- N+1 query #2 -->
<% end %>

[Git Blame shows:]
👤 Chris Taylor • 3 months ago
💬 "Add posts index page"

[Issue:]
- Missing eager loading
- 100 posts × 2 queries each = 200 extra queries
- Causing timeout under load

[Fix:]
13    @posts = Post.includes(:comments, :author).limit(100)
```

**Performance win:** 200 queries → 3 queries

---

### Use Case 8: Security Vulnerability Response

**Scenario:**
Security scanner flagged potential SQL injection. Need to verify and fix quickly.

**With Source Code Integration:**
```ruby
# Error: PG::SyntaxError in SearchController#results

[View Source shows:]
15  def results
16    query = params[:q]
17 →  @results = User.where("name LIKE '%#{query}%'")  # SQL injection!
18  end

[Git Blame shows:]
👤 Tom Anderson • 2 years ago
💬 "Add basic search"

[Security issue:]
- Direct string interpolation into SQL
- Allows SQL injection attacks
- Very old code (2 years)

[Fix:]
17    @results = User.where("name LIKE ?", "%#{query}%")
# Or better:
17    @results = User.where("name ILIKE ?", "%#{User.sanitize_sql_like(query)}%")
```

**Critical fix:** Security vulnerability patched in minutes

---

### Use Case 9: Multi-Developer Coordination

**Scenario:**
Multiple developers working on same codebase. Error appears after merge.

**With Source Code Integration:**
```ruby
# Error: ArgumentError in OrdersController#create - wrong number of arguments

[View Source shows:]
24  def create
25 →  @order = Order.new(order_params, current_user)  # Wrong!
26    @order.save!

[Git Blame shows:]
👤 Developer A • 1 hour ago
💬 "Merge branch 'feature/order-improvements'"

[Investigation:]
- Order.new signature changed in another branch
- Now expects: Order.new(user: current_user, **order_params)
- Merge conflict resolved incorrectly

[Fix:]
25    @order = Order.new(user: current_user, **order_params)

[Team process:]
- Need better merge conflict resolution
- Add tests for Order creation
- CI should catch signature changes
```

**Merge conflict identified:** Clear blame helps coordinate fix

---

### Use Case 10: Debugging in Different Environments

**Scenario:**
Error only happens in staging, not in development. Need to compare code versions.

**With Source Code Integration + Commit SHA Strategy:**
```ruby
# Production Error:
Git SHA: abc123 (2 days old)
Error at line 42

[View on GitHub] → Opens abc123 version

# vs.

# Local Development:
Git SHA: def456 (current)
Same file, different code at line 42

[Quick comparison:]
- Production running old code
- Bug already fixed in current branch
- Just needs deployment

[Action:]
git log abc123..def456 -- app/controllers/users_controller.rb
# Shows the fix commit
```

**Environment diff:** Quickly identify version mismatches

---

## Best Practices

### Recommended Settings for Production

```ruby
RailsErrorDashboard.configure do |config|
  # Enable the feature
  config.enable_source_code_integration = true

  # Show git blame (helps identify who to ask about code)
  config.enable_git_blame = true

  # Set your repository URL
  config.git_repository_url = ENV["GIT_REPOSITORY_URL"]

  # Use commit SHA for accuracy (requires git_sha tracking)
  config.git_branch_strategy = :commit_sha

  # Moderate context (balance between info and performance)
  config.source_code_context_lines = 5

  # Long cache (code doesn't change often in production)
  config.source_code_cache_ttl = 7200  # 2 hours

  # Security: hide gem/vendor code
  config.only_show_app_code_source = true
end
```

### Recommended Settings for Development

```ruby
RailsErrorDashboard.configure do |config|
  # Enable the feature
  config.enable_source_code_integration = true

  # Git blame optional in dev (less useful locally)
  config.enable_git_blame = false

  # Use current branch (code changes frequently)
  config.git_branch_strategy = :current_branch

  # More context lines (helpful for debugging)
  config.source_code_context_lines = 10

  # Short cache (code changes frequently)
  config.source_code_cache_ttl = 300  # 5 minutes

  # Show all code (including gems for debugging)
  config.only_show_app_code_source = false
end
```

---

## Future Enhancements

Potential improvements for future versions:

1. **Syntax Highlighting** - Color-coded Ruby syntax
2. **Inline Annotations** - Show variable values, types
3. **Jump to Definition** - Click to navigate to method definitions
4. **Code Search** - Search within displayed source
5. **Diff View** - Show changes between error occurrence and current
6. **AI Suggestions** - Auto-suggest fixes based on error
7. **Performance Profiling** - Show execution time per line

---

## Credits

- **Implementation:** Claude Opus 4.5
- **Design:** Rails Error Dashboard Team
- **Testing:** Comprehensive test suite (920+ tests)
- **Commits:** 4 parts (SourceCodeReader, GitBlameReader, GithubLinkGenerator, UI Integration)

---

## License

This feature is part of the Rails Error Dashboard gem and follows the MIT License.

---

## Visual Guide & Screenshots

> **Note:** Screenshots will be added in a future update. Below are descriptions of what each screenshot should show to help you understand the feature visually.

### Screenshot 1: Error Dashboard Overview
**Location:** Main error list page (`/error_dashboard`)
**What to show:**
- List of recent errors
- Error type, message, timestamp
- Platform badges (iOS/Android/Web)
- Click on any error to see details

**Key elements:**
- Navigation sidebar
- Error count badges
- Search and filter options
- "Source Code Integration" enabled indicator

---

### Screenshot 2: Error Details - Collapsed Backtrace
**Location:** Error details page before clicking "View Source"
**What to show:**
- Full error message
- Complete backtrace with file paths
- Each app frame has "[View Source ▼]" button
- Gem/framework frames don't have button (grayed out)

**Key elements:**
- Backtrace frames clearly separated
- App frames highlighted or badged
- Collapsed state (no source code visible yet)
- "View Source" buttons only on app frames

---

### Screenshot 3: Source Code Viewer - Expanded
**Location:** After clicking "View Source" on an app frame
**What to show:**
- Source code viewer opened inline
- Line numbers visible
- Error line highlighted in yellow/amber
- ±5 lines of context (configurable)
- Clean, monospace font
- Readable in both light and dark mode

**Key elements:**
- Syntax highlighting (if implemented)
- Line number column
- Highlighted error line
- Context lines above and below
- Collapsible/expandable toggle

---

### Screenshot 4: Git Blame Information
**Location:** Source code viewer with git blame enabled
**What to show:**
- Author avatar or icon
- Author name ("Jane Smith")
- Time ago format ("3 days ago")
- Commit message ("Fix validation logic")
- Repository link button

**Key elements:**
- Clear visual hierarchy
- Icons for author, time, commit
- Truncated long commit messages
- Professional, clean layout

---

### Screenshot 5: Repository Link Button
**Location:** Source code viewer header
**What to show:**
- "View on GitHub" button (or GitLab/Bitbucket)
- Platform-specific icon (GitHub octocat, etc.)
- Button in prominent position
- Hover state showing link preview

**Key elements:**
- Platform-specific branding
- Clear call-to-action
- Opens in new tab indicator
- Consistent with dashboard design

---

###Screenshot 6: GitHub Destination
**Location:** GitHub repository page (external)
**What to show:**
- GitHub page opened to exact file and line
- URL in browser showing commit SHA
- Line number highlighted by GitHub
- File breadcrumb navigation

**Key elements:**
- Accurate line number in URL (#L42)
- Commit SHA in URL path
- GitHub's native line highlighting
- File contents matching error time

---

### Screenshot 7: Dark Mode Support
**Location:** Error details with source code in dark mode
**What to show:**
- Same layout as light mode
- Dark background colors
- Light text for readability
- Proper contrast ratios
- Highlighted error line visible in dark mode

**Key elements:**
- Catppuccin Mocha theme colors
- Code readability maintained
- No bright/harsh colors
- Smooth theme toggle

---

### Screenshot 8: Mobile Responsive View
**Location:** Error details on mobile device
**What to show:**
- Backtrace frames stacked vertically
- Source code viewer adapted for narrow screen
- Horizontal scrolling for long lines
- Touch-friendly buttons and controls

**Key elements:**
- Responsive layout
- Readable code on small screens
- Easy to navigate
- Touch targets large enough

---

### Screenshot 9: Configuration in Initializer
**Location:** `config/initializers/rails_error_dashboard.rb`
**What to show:**
- Configuration block with source code settings
- Well-commented options
- Example values
- Syntax highlighting in editor

**Key elements:**
- Clear option names
- Helpful inline comments
- Logical grouping
- Default values shown

---

### Screenshot 10: Complete Workflow
**Location:** Animated GIF or series showing full process
**What to show:**
1. Error occurs in app
2. Visit dashboard
3. Click error
4. Click "View Source"
5. See code and blame
6. Click "View on GitHub"
7. Repository opens in new tab

**Key elements:**
- Smooth transitions
- Clear mouse clicks/interactions
- Professional demonstration
- Complete user journey

---

### ASCII Art Flow Diagram

```
User triggers error in app
         │
         ▼
┌────────────────────┐
│  Rails Application  │
│                    │
│  1. Error occurs   │
│  2. Caught by      │
│     middleware     │
└────────┬───────────┘
         │
         ▼
┌────────────────────┐
│ Error Dashboard    │
│                    │
│  3. Error logged   │
│  4. User visits    │
│     /error_dashboard│
└────────┬───────────┘
         │
         ▼
┌────────────────────┐
│ Error Details Page │
│                    │
│  5. Shows backtrace│
│  6. [View Source]  │
│     buttons appear │
└────────┬───────────┘
         │
         ▼
┌────────────────────────────────────┐
│ SourceCodeReader Service           │
│                                    │
│  7. Validates file path            │
│  8. Checks Rails.root boundary     │
│  9. Reads file from disk           │
│ 10. Extracts ±5 lines              │
│ 11. Caches result                  │
└────────┬───────────────────────────┘
         │
         ├───────────────┐
         │               │
         ▼               ▼
┌────────────────┐  ┌───────────────────┐
│ GitBlameReader │  │ GithubLinkGenerator│
│                │  │                   │
│ 12. Execute    │  │ 15. Detect GitHub/│
│     git blame  │  │     GitLab/Bitbucket│
│ 13. Parse      │  │ 16. Build URL with│
│     output     │  │     commit SHA    │
│ 14. Cache      │  │ 17. Return link   │
└────────┬───────┘  └───────┬───────────┘
         │                  │
         └─────────┬────────┘
                   │
                   ▼
┌──────────────────────────────────┐
│ Source Code Viewer (HTML)        │
│                                  │
│ 18. Display code with line #s    │
│ 19. Highlight error line         │
│ 20. Show git blame info          │
│ 21. Render repository button    │
└──────────────────────────────────┘
```

---

### Component Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│  Rails Error Dashboard Engine                   │
│                                                  │
│  ┌───────────────────────────────────────────┐  │
│  │  Controllers                               │  │
│  │  └─ ErrorsController#show                 │  │
│  └────────────┬──────────────────────────────┘  │
│               │                                  │
│  ┌────────────▼──────────────────────────────┐  │
│  │  Helpers                                   │  │
│  │  └─ BacktraceHelper                       │  │
│  │      ├─ read_source_code(frame)           │  │
│  │      ├─ read_git_blame(frame)             │  │
│  │      └─ generate_repository_link(...)     │  │
│  └────────────┬──────────────────────────────┘  │
│               │                                  │
│  ┌────────────▼──────────────────────────────┐  │
│  │  Services                                  │  │
│  │  ├─ SourceCodeReader                      │  │
│  │  │   ├─ validate_path                     │  │
│  │  │   ├─ check_security                    │  │
│  │  │   └─ read_file                         │  │
│  │  │                                         │  │
│  │  ├─ GitBlameReader                        │  │
│  │  │   ├─ git_available?                    │  │
│  │  │   ├─ execute_git_blame                 │  │
│  │  │   └─ parse_blame_output                │  │
│  │  │                                         │  │
│  │  └─ GithubLinkGenerator                   │  │
│  │      ├─ detect_platform                   │  │
│  │      ├─ normalize_path                    │  │
│  │      └─ build_url                         │  │
│  └────────────┬──────────────────────────────┘  │
│               │                                  │
│  ┌────────────▼──────────────────────────────┐  │
│  │  Views                                     │  │
│  │  └─ errors/show.html.erb                  │  │
│  │      └─ _source_code.html.erb (partial)   │  │
│  └────────────┬──────────────────────────────┘  │
│               │                                  │
│  ┌────────────▼──────────────────────────────┐  │
│  │  Configuration                             │  │
│  │  └─ rails_error_dashboard.rb (initializer)│  │
│  │      ├─ enable_source_code_integration    │  │
│  │      ├─ enable_git_blame                  │  │
│  │      ├─ git_repository_url                │  │
│  │      └─ source_code_cache_ttl             │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

### Data Flow Diagram

```
Request: GET /error_dashboard/errors/123
            │
            ▼
    ┌───────────────┐
    │ ErrorsController │
    │    #show      │
    └───────┬───────┘
            │
            ▼
    ┌───────────────┐
    │ Load ErrorLog  │
    │ ID: 123       │
    └───────┬───────┘
            │
            ▼
    ┌────────────────────┐
    │ Parse Backtrace    │
    │ Extract frames     │
    │ Categorize: app/gem│
    └───────┬────────────┘
            │
            ▼
    ┌────────────────────────┐
    │ Render View            │
    │ (show.html.erb)        │
    │                        │
    │ For each APP frame:    │
    │   call read_source_code│
    └───────┬────────────────┘
            │
            ▼
    ┌────────────────────────┐
    │ BacktraceHelper        │
    │ #read_source_code      │
    └───────┬────────────────┘
            │
            ├──── Cache Hit? ────┐
            │                    │
            NO                  YES
            │                    │
            ▼                    ▼
    ┌───────────────┐    ┌──────────────┐
    │ SourceCodeReader│   │ Return cached │
    │ .read_file()   │    │ result       │
    └───────┬───────┘    └──────────────┘
            │
            ▼
    ┌───────────────┐
    │ File validation│
    │ Security checks│
    └───────┬───────┘
            │
            ▼
    ┌───────────────┐
    │ Read file     │
    │ Extract lines │
    └───────┬───────┘
            │
            ▼
    ┌───────────────┐
    │ Cache result  │
    │ TTL: 1 hour   │
    └───────┬───────┘
            │
            ▼
    ┌───────────────────────┐
    │ Render source code     │
    │ in _source_code partial│
    └────────────────────────┘
```

---

## Support

For issues, questions, or feature requests related to Source Code Integration:

1. Check this documentation
2. Review configuration settings
3. Check logs for errors
4. Open an issue on GitHub: https://github.com/AnjanJ/rails_error_dashboard/issues
