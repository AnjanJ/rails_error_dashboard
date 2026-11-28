# Handoff

> Written 2026-11-28 on feat/hardening-data-lifecycle (PR 6: T17, T18, T19), after `cc3c4183`; this note is
> the branch's last commit. Nothing is pushed. The push, opening the PR, each later push and the merge each
> need the maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T19 and T30-T36 are done. PRs 1-5, 10 and 11 are squash-merged (#373, #375,
  #377, #378, #379, #381, #383). PR 6 is this branch, not yet pushed. Left, in the maintainer's order
  (2026-11-24): PR 7 (T20-T21), PR 9 (T28-T29), PR 8 (T22-T27). rc.2 is due 2026-12-11.
- The tracking issue is #374, items 1-5, 10 and 11 ticked. Tick PR 6's item (item 6), adding "(#N)", when it
  merges (only with a yes). Change only that line, diff the body before saving, and never close it.

## Done this session (2026-11-28)
- `73fc1201` docs(spec), with the maintainer's "yes to all" of 2026-11-28: REQ-64 (deleted occurrences keep
  their place in the dashboard's counts), REQ-65 (validation), REQ-66 (baseline warning); the retention
  decision's amendment (option 3: fold each batch into its groups' 15-minute `EventCount` buckets); T17-T19's
  file lists; T20 After T18 (a file overlap).
  - Why: a probe on `d21e3748` deleted a live group's occurrences older than 7 days, and its 30-day count went
    from 3 to 1 (first seen 60 days ago); a group first seen 20 days ago kept its total but moved the event to
    its first-seen day.
- `ef762e30` T17 (REQ-23 to REQ-25, REQ-64 to REQ-66): `occurrence_retention_days` (nil, frozen at 1.0).
  `RetentionCleanupJob.expired_occurrences(cutoff)` and `.delete_old_occurrences(cutoff)`: per batch of 1,000,
  pluck, tally by group and bucket, `EventCount.accumulate` each, delete the contexts and the occurrences, in
  one `transaction(requires_new: true)`. A batch whose buckets can't be written rolls back and the pass stops.
  `#perform` expires errors, then occurrences, each with its own rescue; `#occurrences_deleted`. The rake task
  previews and runs with only the new setting. Boot refuses anything but nil or a whole number >= 1, and warns
  under `BaselineCalculator::DAILY_LOOKBACK` (84 days) with baseline alerts on.
  - REQ-64 was narrowed in this commit: a window that starts between two 15-minute boundaries can gain or lose
    the events of its first 15 minutes, as with storm-shed events. Days are exact.
  - 18 deliberate breaks, all caught. "No savepoint" was caught only after an example running the job inside a
    caller's transaction was added: the suite's own transaction is not joinable, so it hides the difference.
  - Worst case on PostgreSQL 16 (1,040 occurrences, each in its own group and bucket): 0.99 s in three runs;
    delete-only 0.005 s. Under the amendment's 2 s bound per batch.
- `52a502a1` T18 (REQ-26): `ApplicationHelper#red_retention_overdue?`, a banner on every page, 3 keys in 11
  locales, an UPGRADING bullet and its copy, a sentence in the `retention_days` rows. The check is cached an
  hour under the analytics cache generation.
  - `issue_fetch_negative_cache_spec`'s broken-cache double now fails `read` too: every page reads the cache
    generation now, and the double's unexpected `read` raised `RSpec::Mocks::MockExpectationError`, which no
    `rescue StandardError` catches.
- `cc3c4183` T19 (REQ-27, REQ-28): `BatchDeleteErrors` deletes through
  `RetentionCleanupJob.delete_with_dependents`. A new spec, spec/commands/batch_delete_errors_spec.rb; the
  older one stays.
- Full suite at `cc3c4183`: 7,567 examples, 0 failures, 9 pending. Lefthook's chaos run: 1,742 passed at each
  code commit. Each task's specs: 0 failures on Rails 7.2.4, 8.0.5.2 and 8.1.4.1, PostgreSQL 16 and MySQL 8.4.
- The shipkit reviewer, at `cc3c4183`: PASS, 9 MET (REQ-23 to REQ-28, REQ-64 to REQ-66), nothing beyond the spec,
  no decision unfollowed. It noted that `expire_occurrences` logs a transient store error rather than raising;
  group expiry does the same, so it counted that as following the amendment's "aborts the run".

## Next step
1. Ask the maintainer to push the branch and open PR 6. When CI is green, they decide on the squash merge;
   then, with a yes, tick #374's item 6, adding "(#N)". Then PR 7 (T20-T21) from the new main.

## Open questions
- The 9 "Host conditions" CI rows: adding them to main's ruleset is a GitHub setting and needs a yes.
- Release-please's #376 must not be merged; rc.2 is cut with a `Release-As: 1.0.0-rc.2` commit. The rc.2 notes
  must say a manual `gem push` needs MFA, that notifications now retry (duplicates; the delivery header), that
  `log_level` defaults to `:error`, that captures inside a host transaction wait for it to end, and now that
  `occurrence_retention_days` exists and that the overdue-retention banner can appear after an upgrade.
- The Upgrade Path job runs only on release PRs and migration PRs (a CI change needs a yes). The intermittent
  sync-app E0 chaos failure from PR 5 didn't recur in this branch's three chaos runs: watch.
- Not verified: the REQ-52 test "stops counting blocks Rails never ran" relies on `GC.start` collecting lost
  waiters; it passed every run so far.
- Not changed: `BaselineCalculator` reads no `EventCount` buckets, so baselines skip storm-shed events and the
  events of deleted occurrences alike (REQ-66 warns; it doesn't fix).
- Housekeeping, untouched: dependabot #371, #372, #380; four old worktrees beside the repo; PROJECT_MAP.md
  stale; ROADMAP "Next up"; `_guides/notifications.md` missing "Muting Notifications"; `CreateIssueJob`'s
  unreachable rescue; SimpleCov deprecation warnings; spec/integration/host_conditions_spec.rb cites the slug
  and REQ numbers apart; debug detail lines double the "[RailsErrorDashboard]" prefix.

## Do not forget
- **Occurrence rows are timestamps:** `EventVolume` counts ordinary events by them and storm-shed and retained
  events by `EventCount` buckets. Anything that deletes occurrence rows of a live group must bucket them first.
- **The test transaction isn't joinable:** a plain `transaction` inside a spec gets a savepoint anyway. To test
  a rollback, also run the code inside `ErrorLogsRecord.transaction { }`.
- **A test double for `Rails.cache`** must answer every method the page calls; an unexpected message raises an
  RSpec error that isn't a `StandardError`.
- **Log lines in tests:** a capture-path failure writes "Capture failure in <site>: <Class> …" at `:error`.
  The suite resets `CaptureFailureLog` before each example.
- **Other Rails versions for specs:** `tasks/scratch/rails72/Gemfile` and `tasks/scratch/rails80/Gemfile` are
  bundled; run with `RAILS_VERSION=<x.y> BUNDLE_GEMFILE=<that>`. The repo's Gemfile.lock stays on 8.1.4.1.
- **MySQL 8.4 locally:** never touch the Homebrew `mysql` service on 3306. Docker Desktop has to be running;
  recreate the container with `docker run -d --name red-mysql84 -e MYSQL_ROOT_PASSWORD=red -e
  MYSQL_DATABASE=red_test -p 127.0.0.1:3307:3306 mysql:8.4`, then load the time zone tables.
- **PostgreSQL 16** on /tmp:5432: `createdb -h /tmp <name>`, `DATABASE_URL="postgres:///<name>?host=/tmp&pool=10"`.
- **`:inline` runs jobs on the reporting thread:** a job that needs another answer to an unschedulable retry
  overrides `retry_unschedulable`, never `retry_job`.
- **A spy keeps the method it finds**; run a timing example alone before trusting it.
- **Rails reports an exception object once:** each report in a test needs its own exception.
- **zsh doesn't split `$var`:** use `${=var}` or arrays. RSpec prints "1 example": grep `examples?`.
- **spec-check's file rule:** of two tasks listing one file, the later in tasks.md must be After the earlier,
  even when it runs first (T30 after T20, T34 after T27, T20 after T18: file overlaps only).
- **Commit signing goes through 1Password**; after a long hook it can fail ("failed to fill whole buffer"):
  HEAD doesn't move, files stay staged; ask the maintainer to unlock, then retry.
- **Agents and the working tree:** start a reviewer with `isolation: "worktree"`, give it the branch SHA, have it
  read with `git diff <base> <sha>` and `git show <sha>:<path>`, and check `git status`, `git stash list`, the
  reflog and `git worktree list` afterwards.
- Rules: commit with `LEFTHOOK_EXCLUDE=chaos-tests` only for docs-only commits; write "Refs #N"; one commit per
  task, staged by name; every merge, release, push or setting change needs a yes.
