---
layout: default
title: "Source Code Integration"
permalink: /docs/SOURCE_CODE_INTEGRATION
---

# Source Code Integration

On an error's page, RED can show the source code around each line of your app in the backtrace,
who last changed that line (git blame), and a link to the same line in your repository. It is off by
default.

1. [What you get](#what-you-get)
2. [Setting it up](#setting-it-up)
3. [Configuration reference](#configuration-reference)
4. [How it works](#how-it-works)
5. [Security](#security)
6. [Syntax highlighting](#syntax-highlighting)
7. [Troubleshooting](#troubleshooting)

---

## What you get

In the backtrace on an error's page, each line from your app's `app/` and `lib/` directories gets a
**View Source** button. Lines from gems, Rails and Ruby don't, with one exception: a gem that has
its own `app/` directory, such as Devise or RED itself, gets the button too, and its viewer says
"Invalid or unsafe file path". The button opens a viewer with:

- **The code around the line**: 5 lines before and after by default, with syntax highlighting and
  the failing line highlighted. The rows are numbered from 1, not with the file's line numbers; the
  viewer's header gives the file and line.
- **Git blame**, if you turn it on: the author of the last change to that line, how long ago it was,
  and its commit message.
- **A link to your repository**, if you set its URL: a **View Source** button with an external-link
  icon that opens the line on GitHub, GitLab, Bitbucket, Codeberg, Gitea or Forgejo. Its tooltip
  says "View on GitHub", "View on GitLab" or, for the others, "View on Bitbucket".

The code comes from the file on your server as it is now. After a deploy that changed the file, the
viewer shows the new code, not what ran when the error happened. The repository link can point at
the code as it was; see [Which commit the links use](#which-commit-the-links-use).

With source code integration on, two other features use it:

- **Copy for LLM** on an error's page adds a few lines of source around lines near the top of the
  backtrace. It reads the files each time, without the cache.
- **Line coverage**: with `enable_coverage_tracking`, the viewer can mark which lines ran.

---

## Setting it up

### Step 1: the source viewer

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
end
```

Restart the app. Then open an error whose backtrace goes through your code, and click **View
Source** next to one of your app's lines.

RED reads the file at the path in the backtrace, starting from your app's root (`Rails.root`). It
has to exist there on the server that shows the dashboard.

### Step 2: git blame

```ruby
config.enable_git_blame = true
```

Blame runs `git blame` on the server, so it needs:

- `git` installed on the server;
- the app's `.git` directory in the deployed app's root. Most Docker images and Capistrano releases
  don't include it, and there blame shows nothing;
- the file committed.

### Step 3: repository links

```ruby
config.git_repository_url = ENV["GIT_REPOSITORY_URL"] # e.g. "https://github.com/myorg/myapp"
```

`git_repository_url` reads `GIT_REPOSITORY_URL` by default, so setting that variable is enough.
RED links only `http` and `https` URLs, and removes a trailing `.git` or `/`.

RED knows the repository host from the URL's host name:

| Host | Link format |
|---|---|
| `github.com` (and `*.github.com`) | `https://github.com/org/app/blob/<ref>/app/models/user.rb#L42` |
| `gitlab.com`, or a host containing `gitlab.` | `https://gitlab.com/org/app/-/blob/<ref>/app/models/user.rb#L42` |
| `bitbucket.org`, or a host containing `bitbucket.` | `https://bitbucket.org/org/app/src/<ref>/app/models/user.rb#lines-42` |
| `codeberg.org`, or a host containing `gitea.` or `forgejo.` | `https://codeberg.org/org/app/src/commit/<sha>/app/models/user.rb#L42` (`src/branch/<name>` for a branch) |

Any other host, such as GitHub Enterprise at `github.example.com` or `git.example.com`, gets no
link.

The path in the link is the part of the backtrace path from the last `app/`, `lib/`, `config/`,
`db/`, `spec/` or `test/` in it. That matches the repository only when the Rails app is at the
repository's root. An app in a subdirectory of its repository gets links that 404.

### Which commit the links use

`config.git_branch_strategy` picks the `<ref>` in each link:

| Strategy | The link points at |
|---|---|
| `:commit_sha` (the default) | The commit RED recorded for the error when it first happened |
| `:current_branch` | The commit the server's app directory is at now (`git rev-parse HEAD`; needs `.git`) |
| `:main` | The `main` branch |

When there is no commit to use, the link points at `main`. There is no setting for another branch
name, so a repository whose default branch is `master` gets links that 404 unless a commit is
known.

For `:commit_sha`, RED records each new error's commit from, in order: `config.git_sha`, the
`GIT_SHA` environment variable (which is also `git_sha`'s default), `HEROKU_SLUG_COMMIT`,
`RENDER_GIT_COMMIT`, and the commit in the app's `.git` directory. So on Heroku (with dyno metadata
on) and Render there is nothing to set. Elsewhere, set `GIT_SHA` at deploy time:

- **Docker:** pass it at build time and keep it in the image:

  ```dockerfile
  ARG GIT_SHA
  ENV GIT_SHA=$GIT_SHA
  ```

  `docker build --build-arg GIT_SHA=$(git rev-parse HEAD) .`
- **Kamal:** add `GIT_SHA` to `env:` in `config/deploy.yml`, or bake it into the image as above.
- **Heroku:** `heroku labs:enable runtime-dyno-metadata` sets `HEROKU_SLUG_COMMIT`, which RED reads.
- **systemd or Capistrano:** set `GIT_SHA` in the environment the app server starts with (for
  example `Environment=GIT_SHA=...` in the unit). A line added to `~/.bashrc` doesn't reach it.

An error keeps the commit from its first occurrence. Occurrences after a later deploy don't change
it.

### Check it works

```bash
bin/rails runner 'c = RailsErrorDashboard.configuration; p [c.enable_source_code_integration, c.git_repository_url, c.git_branch_strategy, ENV["GIT_SHA"]]'
```

Then trigger an error in one of your controllers, open it in the dashboard, and click **View
Source** on the controller's line.

---

## Configuration reference

| Option | Default | |
|---|---|---|
| `enable_source_code_integration` | `false` | Turns on the viewer, blame and links |
| `source_code_context_lines` | `5` | Lines shown before and after the error line. At least 1, at most 50 |
| `enable_git_blame` | `false` | Shows blame. Needs `enable_source_code_integration` |
| `git_repository_url` | `ENV["GIT_REPOSITORY_URL"]` | Your repository's web URL. Also used by issue tracking |
| `git_branch_strategy` | `:commit_sha` | `:commit_sha`, `:current_branch` or `:main`; any other value links to `main` |
| `git_sha` | `ENV["GIT_SHA"]` | The deployed commit |
| `source_code_cache_ttl` | `3600` | Seconds RED caches each line's source and blame |
| `only_show_app_code_source` | `true` | Refuses to read files under `/gems/`, `/vendor/bundle/`, `/vendor/ruby/` or `/.bundle/` |

Environment variables RED reads for this feature: `GIT_REPOSITORY_URL`, `GIT_SHA`,
`HEROKU_SLUG_COMMIT` and `RENDER_GIT_COMMIT`.

A setup for production, with the variables set by your deploy:

```ruby
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  config.enable_git_blame = false # most production images have no .git
  config.git_branch_strategy = :commit_sha
end
```

---

## How it works

- **When:** when an error's page is rendered, RED reads the code for every app line in the
  backtrace, runs blame for each if it is on, and builds each link. The viewers start closed, but
  the work is already done. On a long backtrace, the first view of an error can take a moment.
- **Caching:** each line's source and blame are cached in `Rails.cache` for
  `source_code_cache_ttl` seconds, keyed by the file and line number. Errors that share a line share
  the cache entry.
- **The page is cached too.** Where fragment caching is on, as it is in production, the error's
  details section, with its backtrace, viewers, blame and links, is cached until the error changes:
  it happens again, or its status, assignee or priority changes. So after you change any setting on
  this page, an error you have already opened keeps showing what it showed. See
  [Clearing the cache](#clearing-the-cache).
- **Reading:** RED reads only the lines it shows, from the file at the backtrace path relative to
  `Rails.root`.
- **Blame:** `git blame -L <line>,<line> --porcelain -- <file>`, run in `Rails.root`, with a 5-second
  timeout.

---

## Security

Anyone who can log in to the dashboard can read the code it shows and the authors' names from blame.
RED limits what it reads:

- Only files under your app's directory (`Rails.root`), and no path containing `..`.
- Never files whose path matches `.env`, `secrets.yml`, `credentials.yml`, `database.yml`,
  `master.key`, `private_key`, `.pem` or `.key`.
- No files over 10 MB, and no binary files (a NUL byte in the first 8 KB).
- With `only_show_app_code_source` (the default), nothing under `/gems/`, `/vendor/bundle/`,
  `/vendor/ruby/` or `/.bundle/`.
- `git blame` runs with an argument list, not through a shell, with `--` before the file name.
- Repository links are built only from `http` and `https` URLs.

RED only reads files. It never writes to your app's directory.

---

## Syntax highlighting

The dashboard highlights code in the browser with highlight.js 11.9.0 (its common build, which has
36 languages), loaded from the jsDelivr CDN with a line-numbers plugin. The language comes from the
file's extension; files RED has no mapping for are shown as plain text. ERB templates have no
grammar in that build, so a view's lines appear with line numbers but no colors.

The viewer needs JavaScript: it opens with Bootstrap's collapse, and the line numbers and the
highlighted error line are added in the browser. The colors are RED's own, in both light and dark
mode.

### With a Content Security Policy

The dashboard's pages load scripts and stylesheets from `cdn.jsdelivr.net` and fonts from Google
Fonts, and use inline styles. RED adds your nonce to its inline scripts when you have a nonce
generator. A policy that allows the dashboard:

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self, "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline, "https://cdn.jsdelivr.net", "https://fonts.googleapis.com"
    policy.font_src    :self, :data, "https://cdn.jsdelivr.net", "https://fonts.gstatic.com"
    policy.img_src     :self, :data, :https # issue trackers' avatars
  end
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
```

---

## Troubleshooting

### Source code not showing

- **No View Source button:** check `enable_source_code_integration` is on, and restart the app.
  Only lines in your app's `app/` and `lib/` (and gems with an `app/` directory) get the button. An
  error you opened before turning it
  on shows its cached page until it happens again; [clear the cache](#clearing-the-cache) to see the
  button now.
- **"Could not read source: File not found or not readable":** the file isn't at
  `Rails.root` plus the backtrace path on the server showing the dashboard. A file deleted or moved
  since the error happened shows this too.
- **"Could not read source: Invalid or unsafe file path":** the path is outside `Rails.root`, has
  `..`, matches a sensitive-file pattern, or is gem or vendor code (see [Security](#security)).
- **"File too large" or "Binary file cannot be displayed":** the file is over 10 MB, or not text.
- **Every `lib/` or `config/` line says "File not found", on an app whose root is `/app`** (Heroku,
  and many Docker images): RED stores `/app/lib/x.rb` as `app/lib/x.rb`, then looks for
  `Rails.root/app/lib/x.rb`. Lines under `app/` read fine.

With `config.enable_internal_logging = true` and `config.log_level = :debug`, RED logs why it
refused a path. A missing file isn't logged.

### Git Blame Not Working

Source shows but no author line:

1. Check `enable_git_blame` is on.
2. Check `git` is installed on the server: `git --version`.
3. Check the app's `.git` directory is there: run `git rev-parse --git-dir` in the app's root on the
   server. Docker images and Capistrano releases usually leave it out; then blame can't work there.
4. Run what RED runs, from the app's root:

   ```bash
   git blame -L 42,42 --porcelain -- app/controllers/users_controller.rb
   ```

   An uncommitted file, a shallow clone without that line's history, or a file over the 5-second
   timeout makes it fail.

From a console, the reader returns the blame or `nil`, and `error` says why:

```ruby
reader = RailsErrorDashboard::Services::GitBlameReader.new("app/controllers/users_controller.rb", 42)
reader.read_blame # => { sha:, author:, email:, date:, commit_message:, line: }, or nil
reader.error      # => "Git not available", "File not found", "Git blame failed: ...", ...
```

Blame shows the last commit that touched the line, which may be a reformatting commit, and it reads
the working tree on the server, not the commit that raised the error.

### Repository Links Not Generating

1. Check `config.git_repository_url` is set, starts with `http://` or `https://`, and its host is
   one RED knows (see [the host table](#step-3-repository-links)).
2. Check the strategy: with `:commit_sha`, the error needs a recorded commit. An error recorded
   before RED could find one (see [Which commit the links use](#which-commit-the-links-use)) links
   to `main`.
3. Build a link from a console. When there is no link, `error` says why, except when the URL is
   blank: then both are `nil`.

   ```ruby
   generator = RailsErrorDashboard::Services::GithubLinkGenerator.new(
     repository_url: RailsErrorDashboard.configuration.git_repository_url,
     file_path: "app/controllers/users_controller.rb",
     line_number: 42,
     commit_sha: RailsErrorDashboard::ErrorLog.last&.git_sha
   )
   generator.generate_link # => "https://github.com/..." or nil
   generator.error         # => "Unsupported repository type", ...
   ```

### Links open the wrong file or a 404

- The repository's default branch is `master` and no commit is known: links use `main`.
- The commit isn't pushed to the repository.
- The Rails app is in a subdirectory of the repository (see the path rule in
  [Step 3](#step-3-repository-links)).
- `:current_branch` on a server without `.git` falls back to `main`.
- You changed `git_repository_url` or `git_branch_strategy`, and the error's page is still cached
  (see [Clearing the cache](#clearing-the-cache)).

### Error pages are slow

Each app line in a backtrace costs a file read, and a `git blame` with blame on, the first time an
error's page is viewed. Later views come from the cache until the error changes. To make the first
view cheaper:

- turn off `enable_git_blame` where it can't work or isn't needed;
- raise `source_code_cache_ttl`;
- use a shared cache store, so every app server reuses the same entries.

### Clearing the cache

Two caches hold what the viewer shows: each error's rendered details section, until the error
changes, and each line's source and blame, for `source_code_cache_ttl` seconds. After a settings
change, clearing both shows the new result on every error:

```ruby
Rails.cache.clear
```

That clears your app's whole cache. To clear only the source and blame entries:

```ruby
Rails.cache.delete_matched("source_code/*")
Rails.cache.delete_matched("git_blame/*")
```

That alone doesn't refresh an error page that is already cached, and it works only with the memory,
file and Redis cache stores: Solid Cache and Memcached don't support `delete_matched`. To turn
caching off in development, use `config.cache_store = :null_store`.

---

## Related Documentation

- [Configuration Guide](guides/CONFIGURATION.md) - Every option
- [Settings Dashboard](guides/SETTINGS.md) - Check what the running app loaded
