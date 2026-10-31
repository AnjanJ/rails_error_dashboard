---
description: Update the live demo app with the latest released gem version
user-invocable: true
disable-model-invocation: true
---

# /demo-update — Update Demo App

Point the live demo app at a newly released gem version. A workflow in the demo
repo does the update. Your job is to start it, read the result, and do the one part
it can't: seeds and feature cards.

## Usage

- `/demo-update` — update to the latest version on RubyGems

The workflow always targets the latest published version. It can't pick an older one.

## How the automation works

`.github/workflows/update-demo-release.yml` in the demo repo runs at :17 and :47
past each hour, and on demand. When RubyGems has a version the demo doesn't run, it:

1. Reads that version's GitHub Release, and stops if it's a draft or a prerelease.
2. Picks the hero pill's text: the `summary` input, else the notes'
   `<!-- demo-summary: ... -->` comment, else the first `###` heading that isn't
   generic, else the first bullet. It cuts anything over 95 characters, and fails if
   it finds no text at all.
3. Updates the lockfile with `--conservative`, using the Bundler the lockfile names.
4. Copies any new migrations from the gem into `db/migrate`, skipping names the demo
   already has.
5. Writes `config/demo_release.json`, which the hero pill reads, and regenerates the
   schema dumps by migrating.
6. Runs the demo's tests, system tests, RuboCop, Brakeman and bundler-audit. A failure
   here stops the run before anything is pushed.
7. Commits to `main` as `chore: update demo to rails_error_dashboard X.Y.Z`, and Render
   deploys that commit.
8. Polls the live site for up to ten minutes, until the landing page shows the new
   version and four dashboard pages return 200.

Never hand-edit the schema dumps or the lockfile for a release. Step 5 and step 3 exist
because doing that by hand broke the demo.

## Steps

1. **Check the gem is live on RubyGems.** The run needs it there:
   ```bash
   curl -s https://rubygems.org/api/v1/gems/rails_error_dashboard.json | jq -r .version
   ```

2. **Start the workflow**, or let the schedule pick the release up:
   ```bash
   gh workflow run update-demo-release.yml -R AnjanJ/rails_error_dashboard_demo_app
   ```
   Add `-f summary="Short description"` to set the pill's text. On a version the demo
   already runs, that changes only the pill.

3. **Read the result:**
   ```bash
   gh run list -R AnjanJ/rails_error_dashboard_demo_app --workflow update-demo-release.yml --limit 3
   gh run view <run-id> -R AnjanJ/rails_error_dashboard_demo_app --log-failed
   ```
   "Demo already runs X.Y.Z" means the schedule got there first. A failed gate pushes
   nothing, so read the log and fix the cause. A new Brakeman release fails this gate
   until the demo bumps `brakeman`.

4. **Load `/` and read the pill.** The version tag and the summary beside it must
   describe the same release.

5. **Check whether seeds or feature cards need work**, below. Patch releases with no
   user-visible feature don't.

## What the workflow doesn't do

These live in the demo repo. The workflow pushes to its `main`, so pull before you edit:
a local clone falls behind on every release.

### Seeds

`db/seeds.rb` only needs work if the new version added a feature that requires demo
data to show anything.

**The test is not "did the feature ship", it is "can a visitor SEE it".** If you are
about to add a landing-page card for the feature, that card links to a page which must
not be empty. 0.10.0 shipped AI crawler tracking and
`/red/errors/rack_attack_summary` read "no events can be recorded", because nothing
had ever written to that table on the demo.

Seeding notes learned there:
- Check the table's **unique index** before writing rows. `rack_attack_events`
  is keyed on `(rule, match_type, discriminator, path, period_hour,
  application_id)`, so every seeded row must differ in at least one.
- Some tables are **hourly aggregates, not request logs**. Seed buckets
  across a range of hours so the page's time filters have something to do.
- Where a classifier decides what renders (`AiAgentClassifier` here), verify
  your fixture strings against it rather than assuming — and include a
  negative case (Googlebot is named but `ai=false`) so the page demonstrates
  the distinction rather than counting everything as a hit.
- Vary the shape. Flat identical counts across every bucket read as
  synthetic; assistants spiking in working hours while crawlers grind
  steadily reads as traffic.
- **Add the model to the `CLEAR_BEFORE_SEED` block.** `bin/docker-entrypoint`
  reseeds on every boot, so anything missing there accumulates per deploy.
- Guard new model references with `defined?`, so the seed still runs against
  an older gem.

### Feature cards

| What | Where | Auto? |
|---|---|---|
| Hero pill version and summary | `config/demo_release.json` | **yes** |
| Footer / install snippet version | `<%= @version %>` | **yes** |
| **Feature card** | a `.gcell` in the `grid-features` section of `app/views/pages/home.html.erb` | **NO** |
| **Card version badge** | `<span class="vbadge">vX.Y.Z</span>` | **NO** |

For a release with a user-visible headline feature, add a `.gcell` to the
`grid-features` grid, newest first, with a `<span class="vbadge">` naming the version
that introduced it. Badge the version the feature SHIPPED IN, not the current version.
Storm protection stays `v0.8.2` forever.

## Crossing into 1.x

The demo's Gemfile pins `~> 0.9`, and in RubyGems that means `>= 0.9, < 1.0`. It allows
every 0.x minor and nothing from 1.0 on, so the run will fail with `Resolved X, expected
1.0.0` until that line changes. Change it before the 1.0.0 release.

The workflow only accepts a stable `X.Y.Z`, so it won't deploy `1.0.0.rc1`.

## Demo App Details

- **Repo**: `AnjanJ/rails_error_dashboard_demo_app`
- **Location**: `/Users/anjan/code/RED/rails_error_dashboard_demo_app`
- **Live URL**: https://rails-error-dashboard.anjan.dev
- **Credentials**: gandalf / youshallnotpass
- **Toolchain**: Ruby 3.4.5, Bundler 4.0.3
- **Gemfile constraint**: `gem "rails_error_dashboard", "~> 0.9"` (allows every 0.x minor)
- **Platform**: Free Render instance
- **Uptime**: UptimeRobot pings every 5 minutes
- **Features**: ALL analytics enabled, source code + git blame, multi-app, separate DB
- **Seed data**: LOTR-themed (4 kingdoms, 480 errors, 296 comments, Fellowship members)
