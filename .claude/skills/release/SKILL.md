---
description: Gem release workflow — verify, then merge the release-please PR to publish
user-invocable: true
disable-model-invocation: true
---

# /release — Gem Release Workflow

Release a new version of rails_error_dashboard.

**Releases are automated by release-please.** You do not bump the version, write
the changelog, build the gem, tag, or run `gem push` by hand — a workflow does all
of it when the release PR is merged. Your job is to verify the release is safe and
then get approval to merge.

## How the automation works

Every push to `main` runs `.github/workflows/release.yml`, which invokes
release-please. It reads the conventional-commit subjects since the last release
and opens (or updates) a PR titled `chore(main): release rails_error_dashboard X.Y.Z`.
That PR contains only:

- `lib/rails_error_dashboard/version.rb`
- `CHANGELOG.md`
- `.release-please-manifest.json`

Merging that PR triggers the publish half of the same workflow:

```
merge release PR
  -> bundle exec rspec
  -> bundle exec rubocop
  -> git tag (v X.Y.Z and rails_error_dashboard/v X.Y.Z)
  -> GitHub Release (marked Latest)
  -> gem push to RubyGems via OIDC trusted publishing
```

There are **no RubyGems credentials involved** — trusted publishing authenticates
via OIDC. `~/.gem/credentials` is not used and does not need to exist.

The version number is derived from commit types, not chosen by hand:
`fix:` -> patch, `feat:` -> minor, `!`/`BREAKING CHANGE` -> major.
To change what version ships, change the commits, not the PR.

## Steps

1. **Find the release PR**:
   ```bash
   gh pr list --state open --json number,title | grep "chore(main): release"
   ```
   If there isn't one, there are no releasable commits since the last release —
   only `docs`/`test`/`refactor`/`chore` commits, which are hidden from the
   changelog by `.release-please-config.json`. Say so and stop.

2. **Confirm what will ship**:
   ```bash
   gh pr diff <PR> | grep -E "^\+" | grep -E "VERSION|^\+\* "
   ```
   Check the version bump matches the change types (two `fix:` commits should
   produce a patch bump, not a minor).

3. **Run the full local verification** — CI does not run chaos tests:
   ```bash
   bundle exec rspec        # expect 0 failures
   bundle exec rubocop      # expect no offenses
   bin/pre-release-test all # 5 apps, expect 0 failed assertions
   ```

4. **Check CI on the release PR**:
   ```bash
   gh pr checks <PR>
   ```
   All 18 checks must pass. If the PR shows `BLOCKED` with checks stuck at
   `action_required`, GitHub is holding workflow runs because the PR was opened
   by a bot. Approve them:
   ```bash
   gh run list --branch release-please--branches--main--components--rails_error_dashboard \
     --json databaseId,name,status --jq '.[] | select(.status=="completed") | .databaseId'
   gh api -X POST repos/AnjanJ/rails_error_dashboard/actions/runs/<id>/approve
   ```

5. **Confirm the current published version** so you can prove the change later:
   ```bash
   curl -s https://rubygems.org/api/v1/gems/rails_error_dashboard.json | jq -r .version
   ```

## MANDATORY APPROVAL GATE

**STOP HERE.** Tell the user what will ship, that verification passed, and:

> Merging the release PR publishes X.Y.Z to RubyGems. This is irreversible — that
> version number can never be reused.
>
> Ready to publish vX.Y.Z?

**Do NOT merge without an explicit "yes".** Merging the release PR *is* the
publish action. There is no separate, later `gem push` step to gate on.

## Publish

6. **Merge the release PR** (squash — the repo allows no other method, and the
   `chore(main): release` subject is what the workflow keys on):
   ```bash
   gh pr merge <PR> --squash
   ```

7. **Verify all four artifacts**, not just the workflow's exit status:
   ```bash
   curl -s https://rubygems.org/api/v1/gems/rails_error_dashboard.json | jq -r .version
   gh release list --limit 2
   git fetch --tags && git tag --sort=-creatordate | head -2
   git -C . log --oneline -1 origin/main
   ```
   Note: releases are tagged **twice** — `vX.Y.Z` and
   `rails_error_dashboard/vX.Y.Z`. `gh release view vX.Y.Z` fails; the release is
   named with the component prefix. Use `gh release list` instead.

8. **Update the demo app** — see `/demo-update`. Do not do this before the gem is
   actually live on RubyGems; `bundle lock` will silently keep the old version.

## If the publish step fails

A transient failure (flaky test, network blip) can leave the tag and GitHub
Release created but the gem unpublished. `.github/workflows/release.yml` has a
`workflow_dispatch` escape hatch that republishes at the current version on `main`
without re-running release-please:

```bash
gh workflow run release.yml -f version=X.Y.Z
```

Do not re-merge or hand-tag in this situation.

## Important Notes

- **Never close the linked issues.** See `release-rules` — the reporter verifies
  and closes. Avoid `Fixes #NNN` in commits for this reason.
- Git tags and GitHub Releases are separate entities, but release-please creates
  both. Do not create either by hand.
- Do not run `gem build` / `gem push` / `git tag` manually. Doing so alongside the
  automation risks publishing a version the workflow then cannot publish.
- Demo app repo: `AnjanJ/rails_error_dashboard_demo_app`
- Demo site: https://rails-error-dashboard.anjan.dev
