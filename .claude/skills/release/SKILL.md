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

Merging that PR triggers the publish half of the same workflow, one job after
another (watch them with `gh run view <run-id>`):

```
merge release PR
  -> release:    release-please creates the GitHub Release (marked Latest)
                 and the rails_error_dashboard/vX.Y.Z tag
  -> test:       bundle exec rspec, bundle exec rubocop (read-only token)
  -> publish:    `rubygems` environment (main only); rake release tags vX.Y.Z,
                 then pushes the gem to RubyGems via OIDC trusted publishing
  -> smoke-test: checks the live demo against the released gem
```

There are **no RubyGems credentials involved** — trusted publishing authenticates
via OIDC, and only the `publish` job can request that token.
`~/.gem/credentials` is not used and does not need to exist.

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

3. **Run the full local verification** — CI does not run `bin/pre-release-test all`
   (its only chaos run is the `full_upgrade` app, on release PRs):
   ```bash
   bundle exec rspec        # expect 0 failures
   bundle exec rubocop      # expect no offenses
   bin/pre-release-test all # builds 5 apps (one API-only); the summary says "Apps passed: 6"
                            # because the HTTP app records two runs. Expect 0 failed assertions
   ```
   Test the release head, not main. Chaos loads the gem by `path:`, so it tests
   whatever is checked out: `git switch --detach <release head>` first, and switch
   back afterwards. In the main tree a bare `rubocop` also counts gitignored local
   files, so run it on a `git archive` of the head, with `BUNDLE_GEMFILE` pointing
   back at the repo's Gemfile.

4. **Check CI on the release PR**:
   ```bash
   gh pr checks <PR>
   ```
   There are 30 rows. The 29 required checks must pass (the upgrade path runs on a
   release PR), and `Overhead benchmark`, which isn't required, shows as skipped.
   `gh pr checks` shows nothing while runs are held, so read them by head SHA with
   `gh run list --commit <head sha>`. If the PR shows `BLOCKED` with checks stuck at
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

6. **Draft the release notes locally. Don't push them yet.** Write them on a local
   branch cut from the release head, then run `bundle exec rspec spec/docs`. Doc specs
   can catch a problem here that would otherwise fail CI on the release head. Prove any
   link check can fail by breaking one anchor once.

## MANDATORY APPROVAL GATE

**STOP HERE.** Tell the user what will ship, that verification passed, and:

> Merging the release PR publishes X.Y.Z to RubyGems. This is irreversible — that
> version number can never be reused.
>
> Ready to publish vX.Y.Z?

**Do NOT merge without an explicit "yes".** Merging the release PR *is* the
publish action. There is no separate, later `gem push` step to gate on.

## Publish

7. **Put the notes on the release PR, last thing on merge day.** Any later push to
   `main` rebuilds the release PR, which drops the notes and can bring back `closes`
   lines. The GitHub Release page is built from the PR body, so the text goes in two
   places:
   - on the release branch, as a `docs:` commit;
   - in the PR body, with a `<!-- demo-summary: A short description -->` comment for
     the demo's hero pill.

   Then wait for CI on the new head. A human push needs no approval. A PATCH to a PR
   right after a push can return the old head, so re-read it before trusting it.

8. **Merge the release PR** (squash — the repo allows no other method, and the
   `chore(main): release` subject is what the workflow keys on). Use `gh api`, because
   `gh pr merge` hangs here. Compare first, and pin the head so nothing else can slip in:
   ```bash
   R=repos/AnjanJ/rails_error_dashboard
   gh api "$R/compare/main...<head sha>" --jq '{ahead_by, behind_by, files: [.files[].filename]}'
   gh api -X PUT "$R/pulls/<PR>/merge" -f merge_method=squash -f sha=<head sha> \
     -f commit_title='chore(main): release rails_error_dashboard X.Y.Z (#<PR>)' \
     -F commit_message=@<body file>
   ```
   `behind_by` must be 0 and the file list must be what you expect. The body file must
   hold no closing keywords.

9. **Verify all four artifacts**, not just the workflow's exit status:
   ```bash
   curl -s https://rubygems.org/api/v1/gems/rails_error_dashboard.json | jq -r .version
   gh release list --limit 2
   git fetch --tags && git tag --sort=-creatordate | head -2
   git -C . log --oneline -1 origin/main
   gh run list --commit <merge sha>
   ```
   Note: releases are tagged **twice** — `vX.Y.Z` and
   `rails_error_dashboard/vX.Y.Z`. `gh release view vX.Y.Z` fails; the release is
   named with the component prefix. Use `gh release list` instead.

   Read every workflow on the merge commit, not only Release. `Overhead benchmark`
   runs on main alongside the publish, so it can go red after the gem is out. That
   isn't a release failure. If it fails a gated row, stop and ask.

10. **Update the demo app** — see `/demo-update`. Do not do this before the gem is
    actually live on RubyGems.

## If the publish step fails

A transient failure (flaky test, network blip) can leave the tag and GitHub
Release created but the gem unpublished. `.github/workflows/release.yml` has a
`workflow_dispatch` escape hatch that republishes at the current version on `main`
without re-running release-please. It runs the same `test` and `publish` jobs as
a release, and must be dispatched from `main` (the `rubygems` environment refuses
any other branch):

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
