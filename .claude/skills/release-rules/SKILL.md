---
description: Release rules, commit conventions, and issue etiquette for rails_error_dashboard
user-invocable: false
---

# Release & Contribution Rules

## CRITICAL: Never Release Without Approval

**NEVER** execute any of these without explicit user approval:
- **Merging the release PR** (`chore(main): release …`) — this IS the publish
  action. release-please tags, creates the GitHub Release, and pushes the gem to
  RubyGems on merge. Irreversible for that version number.
- `gem push`, `git tag`, `git push origin <tag>`, `gh release create` — all
  handled by the automation. Running them by hand risks a state the workflow
  cannot then publish.

Verify everything (full suite, RuboCop, chaos tests, CI on the release PR), then
STOP and ask: "Ready to publish vX.Y.Z to RubyGems?"

See `release` for the full workflow.

## CRITICAL: Never Close GitHub Issues

Always let the issue reporter verify the fix and close it themselves. When a fix is merged:
1. Comment on the issue with thanks
2. Explain the root cause
3. Describe the fix and which version includes it
4. Ask them to reopen if the issue persists
5. Do NOT close the issue

**Watch for auto-close.** GitHub closes an issue automatically when a merged
commit or PR body contains a closing keyword — `Fixes #NNN`, `Closes #NNN`,
`Resolves #NNN`. That silently violates this rule even though you never ran
`gh issue close`. Write `Refs #NNN` or `See #NNN` instead.

If an issue does auto-close, reopen it and say why:
```bash
gh issue reopen <N> --comment "Reopening so you can verify the fix yourself — it auto-closed from the commit reference."
```

## Commit Message Conventions

Use conventional commits style:
- `feat:` — new feature
- `fix:` — bug fix
- `chore:` — maintenance, deps, version bumps
- `docs:` — documentation only
- `refactor:` — code restructuring without behavior change
- `test:` — adding or fixing tests
- `perf:` — performance improvement

Examples:
```
feat: add N+1 query detection breadcrumb page
fix: resolve SQLite BRIN index migration error
chore: bump version to 0.3.0
docs: add flexible authentication to changelog and README
test: add system specs for deprecation warnings page
refactor: extract notification throttling to service
```

## Version Numbering

Follows semantic versioning (SemVer):
- **Major** (1.0.0) — breaking changes, public API changes
- **Minor** (0.3.0) — new features, backwards-compatible
- **Patch** (0.3.1) — bug fixes only

Current version: defined in `lib/rails_error_dashboard/version.rb`

The bump is **derived from commit types**, not chosen by hand — `fix:` gives a
patch, `feat:` a minor, `!` or `BREAKING CHANGE` a major. To change what version
ships, change the commits. Editing `version.rb` directly will be overwritten by
release-please.

## Release Artifacts

A complete release produces:
1. Version bump + changelog commit on `main` (the merged release PR)
2. RubyGems package, pushed via OIDC trusted publishing — no credentials involved
3. Two git tags: `vX.Y.Z` **and** `rails_error_dashboard/vX.Y.Z`
4. GitHub Release with changelog notes, marked Latest
5. Updated demo app lockfile (see `demo-update`)

Items 1-4 are produced by the automation on merging the release PR. Only item 5
is manual.

## Git Tags vs GitHub Releases

These are **separate entities** — pushing a tag does not by itself create a
GitHub Release, and the "Latest" badge only appears on Releases. release-please
creates both, so neither should be made by hand.

Because releases carry a component prefix, `gh release view vX.Y.Z` reports
"release not found" even when the release exists. Use `gh release list`, or the
full name `rails_error_dashboard/vX.Y.Z`.
