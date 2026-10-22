# Design: CI least privilege

## Shape of `release.yml` after the change

```
permissions: {}                       # nothing at the workflow level

release      (push only)              contents: write, pull-requests: write
  release-please only, no checkout. Output: release_created.

test         needs: release           contents: read
  if: not cancelled, and (dispatched, or release_created)
  1. checkout (persist-credentials: false)
  2. on dispatch only: version input (from env) must equal version.rb, else fail
  3. setup-ruby, no cache; bundle install (all groups)
  4. bundle exec rspec; bundle exec rubocop

publish      needs: test              contents: write, id-token: write
  if: not cancelled, and test succeeded
  environment: rubygems               (only main may deploy)
  env: BUNDLE_WITHOUT: development:test
  1. checkout (fetch-depth: 0, persist-credentials: false)
  2. setup-ruby, no cache; bundle install (runtime group only)
  3. rubygems/release-gem (builds, tags vX.Y.Z, pushes the tag, uploads with attestation)

smoke-test   needs: publish           contents: read, issues: write
  if: not cancelled, and publish succeeded, and event is push
  uses: ./.github/workflows/smoke-test-demo.yml
  secrets: DEMO_USER, DEMO_PASSWORD   (no longer `inherit`)
```

Every third-party action in this file is pinned to a commit SHA with a version comment
(→ REQ-13). The pins keep today's major versions: checkout v5.1.0, setup-ruby v1.332.0,
release-please-action v5.0.0, release-gem v1.4.1. Upgrading majors is Dependabot's job.

`ci.yml` and `test.yml` get `permissions: contents: read` at the top (→ REQ-2), and every checkout
gets `persist-credentials: false` (→ REQ-11). In `ci.yml`'s `upgrade` job, `github.head_ref` and
`github.base_ref` reach the script as `HEAD_REF` and `BASE_REF` (→ REQ-12).

## Decision: one test job and one publish job serve both triggers   (→ REQ-3, REQ-8, REQ-15)

**Context.** Today the push path (`release`) and the dispatch path (`republish`) are two copies
of the same steps: checkout, Ruby, rspec, RuboCop, release-gem. Splitting each into a read-only
test job and a publishing job gives four jobs. The other way is to share one pair between both
triggers. A job that `needs` a skipped job is skipped too unless its `if` says otherwise, and
skips propagate down the `needs` chain. So shared jobs need explicit conditions
(`!cancelled() && …`).

**Alternatives.**
1. One `test` job and one `publish` job, used by both triggers, with explicit `if` conditions.
2. Two pairs: `release` → `test` → `publish`, and `republish-test` → `republish-publish`, each
   pair with the default `if`.

**Case for 1.** Only one job in the file ever holds `id-token: write`, so REQ-3 has one place to
check, and the `rubygems` environment is attached once. The escape hatch can't drift from the real
path, because it is the real path. A dispatch exercises the same publish job a release uses.
`republish` was a hand-kept copy before.

**Case against 1.** The `if` conditions are subtle. If `publish` used the default `if`, a dispatch
would skip it silently: its ancestor `release` is skipped on a dispatch, and the skip propagates.
That failure looks like a quiet non-release, the same family as the earlier `startup_failure`.
The YAML spec can check the text of each condition, but only a real run proves how GitHub
evaluates it.

**Decision.** Option 1. The conditions are written out explicitly
(`!cancelled() && needs.test.result == 'success'`), and the spec pins them.
**Falsifiability.** We would reverse this if a `release.yml` run shows the `test` job succeeded
while `publish` was skipped (or `test` skipped while `release_created` was true).
**Fired-if.** manual <!-- check the first release run's job graph with gh run view -->

## Decision: the publish job installs the runtime group only, through Gemfile groups   (→ REQ-6, REQ-7)

**Context.** `rubygems/release-gem` runs `bundle exec rake release`, so the publish job needs a
bundle. Today every gem in the `Gemfile` is in the default group (pg, trilogy, puma, sqlite3,
rubocop-rails-omakase, lefthook, bundler-audit, rdoc, browser, chartkick, httparty, rack-attack,
turbo-rails, solid_queue). Only the gemspec's `add_development_dependency` gems land in
`:development`. So `BUNDLE_WITHOUT=development:test` on its own would still install, and build,
almost the whole development bundle in the job that can publish. Native extensions run code at
install time.

**Alternatives.**
1. Move every gem except `rails` and the `json` constraint into `group :development, :test`, and
   set `BUNDLE_WITHOUT=development:test` on the publish job. Keep release-gem as it is.
2. A second, release-only Gemfile (for example `Gemfile.release` with `gemspec` only), selected by
   `BUNDLE_GEMFILE` in the publish job.
3. Drop Bundler from the publish job. Use `gem build`, `configure-rubygems-credentials`,
   `gem push --attestation` with a `sigstore-cli` signature, and a hand-written tag push.

**Case for 1.** It's the smallest change, with one Gemfile. release-gem keeps doing exactly what it
did for 0.16.2: the `vX.Y.Z` tag, the sigstore attestation, waiting for propagation. Development
and CI installs every group by default, so they don't change. The groups also document which gems
are development-only.

**Case against 1.** The publish job still installs the gem's runtime dependencies (Rails and its
tree, pagy, groupdate, concurrent-ruby), about 70 gems, some with native extensions. Those are the
gems every user of the gem installs anyway, but they are third-party code. A gem added to the
Gemfile later, outside the group, would land in the publish job unnoticed, except that the REQ-7
spec fails on it. Option 2 would install the same runtime tree, so it gains little and adds a file
to keep in step. Option 3 removes the bundle entirely, but it re-implements release-gem's tag push
and attestation, and the first proof would be a real release.

**Decision.** Option 1.
**Falsifiability.** We would reverse this (to option 3) if the publish job's `bundle install` log
for a release shows any gem that is not in the runtime dependency tree of
`rails_error_dashboard`, or if release-gem stops creating the attestation (no "attestation" on the
release's rubygems.org version page).
**Fired-if.** manual

## Decision: no Bundler cache anywhere in `release.yml`   (→ REQ-6, REQ-8)

**Context.** `setup-ruby` with `bundler-cache: true` restores a cache that other workflows on
`main` (the `ci.yml` jobs) also write. zizmor flags caches in a publishing workflow
(`cache-poisoning`, two findings today). The test job is read-only, but it decides whether the
publish job runs.

**Alternatives.**
1. `bundler-cache: false` and a plain `bundle install` in both `test` and `publish`.
2. Cache in `test` only; no cache in `publish`.
3. Keep the cache in both.

**Case for 1.** What runs in the release workflow is resolved and installed fresh from RubyGems,
never restored from a cache another workflow wrote. zizmor ends with no `cache-poisoning` findings.

**Case against 1.** Every release spends extra minutes installing gems twice. Releases happen a few
times a week at most, so this costs minutes, not reliability. A RubyGems outage now fails the
release run, where a warm cache might have carried it, but a publish needs RubyGems.org anyway.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if the `test` job's install step takes more than 5
minutes on a release run, or a release run fails in `bundle install` twice in a row.
**Fired-if.** manual

## Decision: pass the smoke test its two secrets by name, not `secrets: inherit`   (→ REQ-14)

**Context.** `smoke-test` calls `smoke-test-demo.yml` with `secrets: inherit`, which hands the
callee every repository secret. The callee reads two: `DEMO_USER` and `DEMO_PASSWORD`, each with a
built-in fallback. The repository has no Actions secrets today (`gh secret list` → `[]`). zizmor
reports this as `secrets-inherit`. This adds **REQ-17** to the accepted spec (below).

**Alternatives.**
1. Declare `DEMO_USER` and `DEMO_PASSWORD` as optional `workflow_call` secrets in the callee, and
   pass exactly those two.
2. Remove `secrets: inherit` and pass nothing (the callee falls back to its defaults).

**Case for 1.** If the maintainer ever sets real demo credentials, the release-time smoke test
uses them, as the scheduled run already would. Nothing else crosses the call.

**Case against 1.** Two more declarations in the callee for secrets that don't exist today.

**Decision.** Option 1.
**Falsifiability.** no clear reversal condition identified: both options pass the same values
today, and option 1 only differs once the secrets exist.

## Spec addition proposed at this gate

- **REQ-17:** The release workflow shall pass the smoke-test workflow only the `DEMO_USER` and
  `DEMO_PASSWORD` secrets.

## Smaller choices (no real alternative)

- **Environment name `rubygems`, branch policy `main`.** It's created with `gh api` as a custom
  deployment-branch policy for exactly `main`, with no reviewers (intake answer 1). If a workflow
  names an environment that doesn't exist, GitHub creates it unprotected, so the environment is
  created before the PR merges.
- **The publish job keeps `contents: write` and `fetch-depth: 0`.** `rake release` pushes the
  `vX.Y.Z` tag before the upload (intake assumptions). Credentials come from release-gem's own
  credential cache, so the checkout persists none.
- **The release job drops its checkout.** release-please works through the API; its README's
  publishing example checks out only for the publish steps.
- **The version check reads `INPUT_VERSION` from `env:`.** It's the first step of `test`, so a
  mismatch fails before rspec, and `publish` never starts (→ REQ-15). The spec runs that script for
  real, with a matching and a mismatched version.

## How the requirements are tested

A new plain-Ruby spec, `spec/ci/workflows_spec.rb`, loads the workflow YAML (Psych reads the key
`on:` as `true`) and evaluates the `Gemfile` with `Bundler::Dsl`.

- REQ-1 to REQ-9, REQ-11 to REQ-14 and REQ-17 are structural assertions on the parsed YAML.
- REQ-15 runs the version-check step's script in a subprocess, once with a matching and once with
  a different `INPUT_VERSION`.

Two requirements can only be checked against GitHub:

- **REQ-10:** `gh api …/environments/rubygems/deployment-branch-policies`.
- **REQ-16:** the first push to `main` after merge (`gh run list --workflow release.yml`, not
  `startup_failure`, with release-please run).

On top of the spec, `actionlint` and `zizmor --offline` run against the changed files. The goal is
no `template-injection`, `excessive-permissions`, `artipacked`, `cache-poisoning` or
`secrets-inherit` finding in the four workflows. `unpinned-uses` stays outside `release.yml` by the
intake answer, and so do the two existing shellcheck notes in `test.yml`, which the spec doesn't
touch.
