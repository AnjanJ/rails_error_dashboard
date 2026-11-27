# Handoff

> Written 2026-11-27 on feat/hardening-capture-failures (PR 11: T33, T36, T34), after `7990195f`; this note is
> the branch's last commit. Nothing is pushed. The push, opening the PR, each later push and the merge each
> need the maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T16, T30-T36 are done. PRs 1-5 and 10 are squash-merged (#373, #375, #377, #378,
  #379, #381). PR 11 is this branch, not yet pushed. Left, in the maintainer's order (2026-11-24): PR 6
  (T17-T19), PR 7 (T20-T21), PR 9 (T28-T29), PR 8 (T22-T27). rc.2 is due 2026-12-11.
- The tracking issue is #374, items 1-5 and 10 ticked. Tick PR 11's item, adding "(#N)", when it merges (only
  with a yes). Change only that line, diff the body before saving, and never close it.

## Done this session (2026-11-26 and 27)
- `4f9c15b6` docs(spec), with the maintainer's "yes to all" of 2026-11-27: REQ-63 and T36 (every RED job's
  unschedulable retry, not only the capture job's); the "capture-path failure" terms counted again on
  `8ccdc73b` (T30's five sites and `AsyncErrorLoggingJob#retry_job` count); the S1 decision's third amendment;
  three notes on how T33 is built.
- `3f992308` T33 (REQ-54 to REQ-58): `Services::CaptureFailureLog.report(site, failure, reported = nil,
  job_id: nil) { detail }`, one summary line per site and failure class a minute, at most 100 keys; the detail
  at debug with `enable_internal_logging`; `Logger.enabled?`; `LogError.loggable_context` and
  `loggable_message`; `log_level` defaults to `:error` (library and template). Every capture-path site, the 4
  in `FlushStormCounts` and the worker's direct lines go through it.
  - 36 examples on Rails 7.2.4, 8.0.5.2 and 8.1.4.1: 0 failures. 15 deliberate breaks, 13 bit (1-20 failures);
    the 2 that didn't change nothing a host sees (`Logger.error` checks `log_level` itself).
  - The spike's 60 s sync storm, storm protection off, Rails 8.1, SQLite, table gone: 12,003 reports wrote 1
    RED line (220 bytes), with 1 error class and with 20 (rc.1: 48,008 writes, 25.1 MB).
  - bin/benchmark against rc.1, idle M3 Max, alternating: async 98 and 107 µs (rc.1 95 and 95), sync 1.13 and
    1.04 ms (rc.1 0.967 and 1.04); storm calm/shedding/open 3.23/4.53/4.30 and 3.49/4.45/4.27 µs (rc.1
    3.33/4.52/4.44 and 3.41/4.51/4.57).
  - Eleven existing examples asserted on rc.1's line text; they now assert on the summary line.
- `73188a9d` T36 (REQ-63): `ApplicationJob#retry_job` rescues `NotImplementedError` and calls the private hook
  `retry_unschedulable(error)` (one line, the attempt ends); `TransientDelivery` overrides the hook to release
  the claim; `AsyncErrorLoggingJob`'s own `retry_job` is gone; `enqueue_after_response` rescues
  `StandardError, ScriptError`.
  - Reproduced first (30 examples, 22 failures): each of the six jobs (four issue-tracker jobs, `StormFlushJob`,
    `BaselineAlertJob`) raised out of `perform_later`; `retry_job` raised on 14 of the 21 job classes; a sync
    capture whose `CreateIssueJob` failed returned nil; `enqueue_after_response` let it out.
  - After: 134 examples (with the notification and capture-job specs) on all three Rails versions, 0 failures.
    Four breaks, each bit. bin/benchmark ran while another process held about 10 cores: both sides slow
    alike (async 161/153 µs, rc.1 152/147); T33's runs are the comparison.
- `92616c83` T34 (REQ-61, prose): CONFIGURATION, SETTINGS, TROUBLESHOOTING, PLUGIN_SYSTEM, BATCH_OPERATIONS
  and their Jekyll copies, UPGRADING (the failed-capture line, and T30's change, with the maintainer's yes),
  the template's logging block and sync comment, `logger.rb`'s comment.
- `7990195f` docs, with the maintainer's yes of 2026-11-27: PUBLIC_API.md's "What's private" lists the wording of
  RED's log lines, except the prefix `[RailsErrorDashboard] Capture failure in`, which stays for 1.x (decision
  0011, tested in capture_failure_log_spec.rb).
- T36's message was reworded before the push (it named a program running on the machine); the rebase kept
  every tree, so `73188a9d` and `92616c83` are `ac256a8b` and `d5a698a6` with new SHAs.
- Full suite 7,531 examples, 0 failures, 9 pending. Lefthook's chaos run: 1,742 passed at each code commit.
- The shipkit reviewer, at `d5a698a6` (now `92616c83`, same tree): PASS, 7 MET (REQ-54 to REQ-58, REQ-61 by reading, REQ-63), no decision
  unfollowed. It noted the Jekyll copies T34 edited (`_guides/`, `_reference/`, `_features/`) were outside the
  spec's Paths line; this commit adds them.

## Next step
1. PR 11 was pushed and opened with the maintainer's yes of 2026-11-27 (`gh pr list` has its number). When CI
   is green the maintainer decides on the squash merge; then, with a yes, tick #374's item 11, adding "(#N)".
   Then PR 6 (T17-T19) from the new main.

## Open questions
- The 9 "Host conditions" CI rows: adding them to main's ruleset is a GitHub setting and needs a yes.
- Release-please's #376 must not be merged; rc.2 is cut with a `Release-As: 1.0.0-rc.2` commit. The rc.2 notes
  must say a manual `gem push` needs MFA, that notifications now retry (duplicates; the delivery header), and
  that `log_level` defaults to `:error`.
- The Upgrade Path job runs only on release PRs and migration PRs (a CI change needs a yes). The intermittent
  sync-app E0 chaos failure from PR 5 didn't recur in this branch's three chaos runs: watch.
- Not verified: the REQ-52 test "stops counting blocks Rails never ran" relies on `GC.start` collecting lost
  waiters; it passed every run so far.
- Housekeeping, untouched: dependabot #371, #372, #380; four old worktrees beside the repo; PROJECT_MAP.md
  stale; ROADMAP "Next up"; `_guides/notifications.md` missing "Muting Notifications"; `CreateIssueJob`'s
  unreachable rescue; SimpleCov deprecation warnings; spec/integration/host_conditions_spec.rb cites the slug
  and REQ numbers apart.

## Do not forget
- **Log lines in tests:** a capture-path failure now writes "Capture failure in <site>: <Class> …" at
  `:error`; rc.1's text is only in the debug detail. The suite resets `CaptureFailureLog` before each example
  (spec/rails_helper.rb), so a second failure in one example with the same key writes no second line.
- **Other Rails versions for specs:** `tasks/scratch/rails72/Gemfile` and `tasks/scratch/rails80/Gemfile`
  (`eval_gemfile` of the repo's Gemfile) are bundled; run with `RAILS_VERSION=<x.y> BUNDLE_GEMFILE=<that>`.
  The repo's Gemfile.lock stays on 8.1.4.1.
- **The spike's storm probe** is extracted to `tasks/scratch/t33/storm/` (boot.rb, storm.rb; see the commit of
  T33 for the env). It needs nothing else running.
- **MySQL 8.4 locally:** the Homebrew `mysql@8.4` keg is gone (only mysql 26.10, its service on 3306: never touch
  it). No test container exists now; image `mysql:8.4` is local. Recreate:
  `docker run -d --name red-mysql84 -e MYSQL_ROOT_PASSWORD=red -e MYSQL_DATABASE=red_test -p
  127.0.0.1:3307:3306 mysql:8.4`. Not needed by PR 11.
- **PostgreSQL 16** on /tmp:5432: `createdb -h /tmp <name>`, `DATABASE_URL="postgres:///<name>?host=/tmp&pool=10"`.
- **`:inline` runs jobs on the reporting thread:** anything that makes a RED job raise for `retry_on` is tested
  with the adapter's `enqueue_at` stubbed to raise `NotImplementedError`, through `perform_enqueued_jobs`. A job
  that needs another answer overrides `retry_unschedulable`, never `retry_job`.
- **A spy keeps the method it finds**; run a timing example alone before trusting it.
- **Rails reports an exception object once:** each report in a test needs its own exception.
- **zsh doesn't split `$var`:** use `${=var}` or arrays. RSpec prints "1 example": grep `examples?`.
- **spec-check's file rule:** of two tasks listing one file, the later in tasks.md must be After the earlier,
  even when it runs first (T30 after T20, T34 after T27: file overlaps only).
- **Commit signing goes through 1Password** and failed once this session after a long hook ("failed to fill
  whole buffer"): HEAD doesn't move, files stay staged; ask the maintainer to unlock, then retry.
- **Benchmarks:** check the load first (`sysctl -n vm.loadavg`); another heavy process doubles the
  medians. rc.1 baseline: `git worktree add --detach /tmp/red-rc1-bench rails_error_dashboard/v1.0.0-rc.1`,
  alternate, then `git worktree remove /tmp/red-rc1-bench` (removed after this session's runs).
- **Agents and the working tree:** start a reviewer with `isolation: "worktree"`, give it the branch SHA, have it
  read with `git diff <base> <sha>` and `git show <sha>:<path>`, and check `git status`, `git stash list`, the
  reflog and `git worktree list` afterwards.
- Rules: commit with `LEFTHOOK_EXCLUDE=chaos-tests` only for docs-only commits; write "Refs #N"; one commit per
  task, staged by name; every merge, release, push or setting change needs a yes.
