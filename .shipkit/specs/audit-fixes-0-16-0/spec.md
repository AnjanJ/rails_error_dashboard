# Spec: Audit fixes for 0.16.0

> Spec accepted at commit `93ba34d` on spec/0-16-0.
> Status: open
> Paths: app/,lib/,db/migrate/20260106094256_backfill_application_for_existing_errors.rb,docs/,_guides/,_features/,_getting_started/,_reference/,bin/pre-release-test,spec/

## Purpose
Fix the defects left from the 2026-10-03 docs audit (`tasks/docs-audit/bugs-0-14-5.md`). A
read-only check against main on 2026-10-15 re-verified 13 of them and found 3 more. #276, #277,
#282 and #283 fixed the rest. Host-app safety first, then correctness, then docs and tooling.

## Requirements (EARS)

### Host-app safety
- **REQ-1.** Where `git_branch_strategy` is `:current_branch`, RED shall build repository links
  without starting a subprocess, from the commit RED resolved at boot (`config.git_sha`, the ENV
  variables, then the detected `.git` HEAD).
- **REQ-2.** When the error page shows co-occurring errors, RED shall run a bounded number of
  queries however many occurrences the error has.

### Correctness
- **REQ-3.** RED shall treat repository URLs ending in `.git`, `.git/`, `/` or `//` as the same
  repository, both in View Source links and in issue tracking.
- **REQ-4.** If an application has errors on only one platform, then Platform Comparison shall not
  rate that platform Critical on volume alone.
- **REQ-5.** Copy for LLM and the AI help context shall take their backtrace lines and source
  snippets from application frames only, in the shortened form RED stores frames in.
- **REQ-6.** RED shall resolve the application name the same way everywhere: the backfill
  migration, the `backfill_application` task, and the Rack::Attack, missing-translation and
  swallowed-exception flushers shall use `config.application_name` first, exactly as capture does.
- **REQ-7.** RED shall extract similarity frames from both backtrace styles: Ruby 3.3's
  `` in `method' `` and Ruby 3.4's `in 'Class#method'`.
- **REQ-8.** When a Settings group header is clicked once, the group shall fold.
- **REQ-9.** If `git_branch_strategy` is not `:commit_sha`, `:current_branch` or `:main` (as a
  Symbol or String), then `validate!` shall report it.
- **REQ-10.** If a webhook arrives for an unknown provider, then RED shall answer 404.
- **REQ-11.** When a batch action fails for some errors, RED shall report the failed ids and
  reasons to the user and to the Rails log, whatever `log_level` is.
- **REQ-12.** When errors are muted in bulk with a reason, RED shall add to each the comment a
  single mute adds.
- **REQ-13.** The Settings page shall count only the options it shows in each group.
- **REQ-14.** The analytics page shall not compute counts it does not render.

### Docs and tooling
- **REQ-15.** The docs and the generated initializer shall say that Devise helpers such as
  `current_user` work inside `authenticate_with`, and that only helpers defined in the host's own
  `ApplicationController` do not. [untested: prose, checked in a real Devise app]
- **REQ-16.** ADVANCED_ERROR_GROUPING, PLATFORM_COMPARISON and OCCURRENCE_PATTERNS (and their
  Jekyll copies) shall match the code for every claim the 2026-10-15 check listed. [untested:
  prose, verified by reading against the code]
- **REQ-17.** Every relative link and anchor in `docs/`, `_guides/`, `_features/`,
  `_getting_started/`, `_reference/` and the READMEs shall resolve.
- **REQ-18.** `ManualErrorReporter.report`'s `@return` shall list every case that returns `nil`.
  [untested: prose]
- **REQ-19.** When `bin/pre-release-test` finishes, no server it started shall still be listening.

## Out of scope
- New features. This spec only fixes defects and the docs that describe them.
- The other 0.16.0 specs (`occurrence-context-history`, `capture-source`).
