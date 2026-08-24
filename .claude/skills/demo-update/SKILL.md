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

7. **UPDATE THE LANDING-PAGE COPY. This is the step that gets missed.**

   `app/views/pages/home.html.erb` has three places that describe *what* the
   release contains. None of them update themselves, and the version number
   sitting next to them DOES — so a stale headline reads as a fresh claim about
   the new version. The hero pill shipped reading
   `v0.9.0 · Storm protection` for two releases after storm protection landed
   in 0.8.2.

   | What | Where | Auto? |
   |---|---|---|
   | Hero pill version tag | `<span class="pill-tag">v<%= @version %></span>` | **yes** — `@version` is `RailsErrorDashboard::VERSION` |
   | **Hero pill headline** | the `<span>` right after it | **NO — hardcoded** |
   | **Feature card** | a `.gcell` in the `grid-features` section | **NO** |
   | **Card version badge** | `<span class="vbadge">vX.Y.Z</span>` | **NO** |
   | Footer / install snippet version | `<%= @version %>` | **yes** |

   For a release with a user-visible headline feature:
   - Rewrite the hero pill headline to name it (short — it sits on one line).
   - Add a `.gcell` to the `grid-features` grid, newest first, with a
     `<span class="vbadge">` naming the version that introduced it.
   - Badge the version the feature SHIPPED IN, not the current version. Storm
     protection stays `v0.8.2` forever.

   For a patch release with no user-visible feature (a security or bug fix),
   leave the copy alone — the version numbers update themselves.

   Verify by loading `/` and reading the pill: the version tag and the headline
   beside it must describe the same release.

8. **Commit and push**:
   ```bash
   git add Gemfile.lock            # add Gemfile too only if you edited it
   git add app/views/pages/home.html.erb   # if you changed the copy in step 7
   git commit -m "chore: update rails_error_dashboard to X.Y.Z"
   git push origin main
   ```

9. **Confirm the deploy** — Render redeploys automatically; the site updates
   within a few minutes. Load the dashboard and confirm the footer version, and
   load `/` to confirm the hero pill reads correctly.

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
