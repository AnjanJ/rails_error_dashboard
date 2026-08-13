---
description: Update the live demo app with the latest released gem version
user-invocable: true
disable-model-invocation: true
---

# /demo-update — Update Demo App

Point the live demo app at a newly released gem version. Render auto-deploys on
push to `main`.

## Usage

- `/demo-update` — update to the latest released version
- `/demo-update 0.8.4` — update to a specific version

## Before you start

**The gem must already be live on RubyGems.** If it isn't, `bundle lock` silently
re-resolves to the previous version and you push a no-op. Check first:

```bash
curl -s https://rubygems.org/api/v1/gems/rails_error_dashboard.json | jq -r .version
```

**The Gemfile usually does not need editing.** It pins `~> 0.8`, which already
allows any 0.8.x. Only the lockfile changes for a patch or minor release within
that range. Edit the Gemfile only when crossing outside the constraint (e.g. 0.8 -> 0.9).

## The lockfile hazard

A plain `bundle lock --update=rails_error_dashboard` run with the wrong Bundler
will quietly wreck the lockfile. Observed on a real update:

- **`BUNDLED WITH` downgraded 4.0.3 -> 2.6.9**, because the local Ruby shipped an
  older Bundler than the demo expects
- **8 unrelated gems bumped** (`rack`, `zeitwerk`, `json`, `reline`, `erb`,
  `io-console`, `rbs`)
- **local platform added** (`arm64-darwin-23`), which does not belong in a
  lockfile deployed to Linux

Any of these can break the Render deploy for reasons unrelated to the gem bump.
The demo pins **Ruby 3.4.5** and **Bundler 4.0.3** — match both.

## Steps

1. **Verify the target version is published** (see above).

2. **Use the demo's Bundler**, not whatever is on PATH:
   ```bash
   gem install bundler -v 4.0.3 --no-document   # once per machine
   ```

3. **Update the lockfile conservatively** — `--conservative` stops Bundler
   bumping unrelated gems:
   ```bash
   cd /Users/anjan/code/RED/rails_error_dashboard_demo_app
   bundler _4.0.3_ lock --conservative --update=rails_error_dashboard
   ```
   Use `bundle lock`, never `bundle install` — installing compiles native gems
   (sqlite3 does not build cleanly on recent macOS) and is unnecessary here.

4. **Remove the local platform line** if Bundler added one. It re-adds the
   running machine's platform on every resolve, so strip it after the final
   `lock` and do not re-resolve afterwards:
   ```bash
   sed -i '' '/^  arm64-darwin-2[0-9]$/d' Gemfile.lock   # keep 24/25 if already tracked
   ```
   Check `PLATFORMS` afterwards — it must still list `x86_64-linux` for Render.

5. **Review the diff before committing.** A clean patch bump is exactly two
   lines, the version and its checksum:
   ```bash
   git diff Gemfile.lock | grep -E "^[+-]" | grep -v "^[+-][+-]"
   ```
   If you see `BUNDLED WITH`, unrelated gem versions, or new platforms, reset with
   `git checkout Gemfile.lock` and redo from step 2.

6. **Check whether the seed file needs updating** — `db/seeds.rb` only needs work
   if the new version added a feature that requires demo data to show anything.

7. **Commit and push**:
   ```bash
   git add Gemfile.lock            # add Gemfile too only if you edited it
   git commit -m "chore: update rails_error_dashboard to X.Y.Z"
   git push origin main
   ```

8. **Confirm the deploy** — Render redeploys automatically; the site updates
   within a few minutes. Load the dashboard and confirm the footer version.

## Demo App Details

- **Repo**: `AnjanJ/rails_error_dashboard_demo_app`
- **Location**: `/Users/anjan/code/RED/rails_error_dashboard_demo_app`
- **Live URL**: https://rails-error-dashboard.anjan.dev
- **Credentials**: gandalf / youshallnotpass
- **Toolchain**: Ruby 3.4.5, Bundler 4.0.3
- **Gemfile constraint**: `gem "rails_error_dashboard", "~> 0.8"`
- **Platform**: Free Render instance
- **Uptime**: UptimeRobot pings every 5 minutes
- **Features**: ALL analytics enabled, source code + git blame, multi-app, separate DB
- **Seed data**: LOTR-themed (4 kingdoms, 480 errors, 296 comments, Fellowship members)
