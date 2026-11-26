# Handoff

> Written 2026-11-26 on feat/hardening-host-conditions (PR 10: T30-T31), after `494d06a6`; this note is the
> branch's last commit. Nothing is pushed. The push, opening the PR, each later push and the merge each need
> the maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T16, T30-T32 and T35 are done. PRs 1-5 are squash-merged (#373, #375, #377, #378,
  #379). PR 10 is this branch, not yet pushed. Left, in the maintainer's order (2026-11-24): PR 11 (T33-T34),
  PR 6 (T17-T19), PR 7 (T20-T21), PR 9 (T28-T29), PR 8 (T22-T27). rc.2 is due 2026-12-11.
- The tracking issue is #374, items 1-5 ticked. Tick PR 10's item, adding "(#N)", when it merges. Change only
  that line, diff the body before saving, and never close it.

## Done this session (2026-11-25 and 26)
- `27761b66` docs: the new order of the pull requests (a dated note at the top of tasks.md).
- `5e126a8d` T30 (REQ-17 to REQ-20, REQ-22, REQ-51 to REQ-53): `Services::CaptureWriteGuard` (defer, allow_writes,
  lease with a `CheckoutBudget` prepend on `ConnectionPool#checkout`), `isolate_capture_writes` and
  `capture_connection_timeout`. design.md amends the S1 record twice, both with the maintainer's yes:
  2026-11-25, bound what a step uses instead of leasing the host's pool; 2026-11-26, the `:inline` fix.
  - The `:inline` bug, found by a probe this session and reproduced on rc.1 too: under `:inline` the capture
    job runs inside `perform_later`; a failed write made `retry_on` schedule a retry, `:inline` raised
    `NotImplementedError` (a ScriptError), and it reached the caller of `Rails.error.report`. Fixed with
    `AsyncErrorLoggingJob#retry_job` (as PR 5's `TransientDelivery`) and `StandardError, ScriptError` in
    `LogError.call` and `ErrorReporter#report`.
  - Full suite 7,465 examples, 0 failures, 9 pending. The 118 T30 examples on SQLite, PostgreSQL 16.16 and
    MySQL 8.4.13, each on Rails 7.2.4, 8.0.5.2 and 8.1.4.1: 0 failures. 55 deliberate breaks, each failed 1-75.
  - bin/benchmark against rc.1, alternating, two runs each: async 110 and 99 µs (rc.1 96 and 99.5), sync 1.13
    and 1.19 ms (rc.1 1.07 and 0.962); a first pair gave sync 1.04 and 1.03 (rc.1 1.12 and 1.01). Storm check
    calm/shedding/open 3.25/4.32/4.41 and 3.14/4.35/4.37 µs (rc.1 3.60/5.07/4.80 and 3.26/4.44/4.80).
- `d8867e87` T31 (REQ-50): `bin/pre-release-test full_host_conditions` (`HOST_DATABASE`, `HOST_DATABASE_URL`,
  `RAILS_VERSION`), `phase_q_host_conditions.rb` (Q0 the Rails and database asked for, Q1 two release
  directories, Q2-Q4 rollback, prevented writes, held pool, sync and async on `:inline`), and a 9-row
  `test.yml` job "Host conditions / <database> / Rails <series>". Local: 24 passed in all 9. Red on rc.1's code:
  8 of 22. Five breaks, each caught by its case.
- `494d06a6` docs: UPGRADING's bullet that notifications retry (decided 2026-11-24).
- Lefthook's chaos run: 1,742 passed at `5e126a8d` and at `d8867e87`.
- The shipkit reviewer: PASS, 9 MET (REQ-17 to REQ-20, REQ-22, REQ-50 to REQ-53), no decision unfollowed.
  It noted that the host spec cites "hardening-1-0-rc2" and the REQ numbers apart, not as
  `hardening-1-0-rc2/REQ-N` (spec-check counts them, 0 gaps; not changed), and that the UPGRADING note is beyond
  T30-T31 (the maintainer's decision of 2026-11-24).

## Next step
1. The maintainer decides on pushing this branch and opening PR 10. Its body needs the capture and storm
   medians against rc.1 (above), "Refs #374", and the Claude Code line.

## Open questions
- **For PR 11 (T33):** seven jobs enqueued from capture code share `ApplicationJob`'s `retry_on` without the
  `:inline` guard: the issue-tracker jobs, `NotificationBurstSummaryJob`, `BaselineAlertJob`, `StormFlushJob`,
  `StormNotificationJob`, `SwallowedExceptionFlushJob`, `RackAttackFlushJob`. Not probed. The widened outer
  rescue covers whatever runs under `LogError.call`; the rest is unchecked. Noted under T33 in tasks.md.
- The 9 CI rows have never run on GitHub: `gem install rails -v "~> <series>.0"`, the mysql2 build and the
  services are proven locally only. The job is not a required check; adding it to main's ruleset is a
  GitHub setting and needs a yes.
- Whether UPGRADING should also describe T30's change (captures wait for the host's transaction; the two
  settings). T34 edits UPGRADING; not decided.
- The installer template's sync comment says "~1-5ms" (measured 3.23-16.38 ms): fix in T34.
- Release-please's #376 must not be merged; rc.2 is cut with a `Release-As: 1.0.0-rc.2` commit. The rc.2 notes
  must say a manual `gem push` needs MFA, and that notifications now retry (duplicates; the delivery header).
- The Upgrade Path job runs only on release PRs and migration PRs (a CI change needs a yes). The intermittent
  sync-app E0 chaos failure from PR 5 didn't recur in this branch's two chaos runs: watch.
- Not verified: the REQ-52 test "stops counting blocks Rails never ran" relies on `GC.start` collecting lost
  waiters; it passed every run so far.
- Housekeeping, untouched: dependabot #370-372, four old worktrees beside the repo, PROJECT_MAP.md stale,
  ROADMAP "Next up", `_guides/notifications.md` missing "Muting Notifications", `CreateIssueJob`'s unreachable
  rescue, SimpleCov deprecation warnings.

## Do not forget
- **MySQL 8.4 locally:** the Homebrew `mysql@8.4` keg is gone (only mysql 26.10, its service on 3306: never touch
  it). Docker container `red-pr10-mysql84` (image `mysql:8.4`, 8.4.13, as CI) on 127.0.0.1:3307, root password
  `red`. Specs: `trilogy://root:red@127.0.0.1:3307/<db>?pool=10`; chaos: `mysql2://root:red@127.0.0.1:3307/<db>`.
  Kept until PR 10's CI is green, then `docker rm -f red-pr10-mysql84`.
- **PostgreSQL 16** on /tmp:5432: `createdb -h /tmp <name>`, `DATABASE_URL="postgres:///<name>?host=/tmp&pool=10"`.
- **Other Rails versions for specs:** a Gemfile with `eval_gemfile "<repo>/Gemfile"`, then `RAILS_VERSION=7.2
  BUNDLE_GEMFILE=<that> mise exec ruby@3.4.5 -- bundle install --local`. The repo's Gemfile.lock stays on 8.1.4.1.
  For chaos, `RAILS_VERSION=<series> bin/pre-release-test full_host_conditions` uses the installed rails gem.
- **A spy keeps the method it finds.** `allow(pool).to receive(:checkout).and_call_original` set before
  `CheckoutBudget` is prepended bypasses the bound, so an example run alone timed the pool's own wait.
  `with_pool_drained` runs a lease first. Run a timing example alone before trusting it.
- **Rails reports an exception object once** (`@__rails_error_reported`): a second `Rails.error.report` of
  the same object does nothing. Each report in a test needs its own exception.
- **Never copy an open SQLite database from the process using it.** Phase Q's first version copied the whole
  app, storage/ included, and a later new connection failed on "disk I/O error" (2 runs of 2); copying the code
  alone fixed it.
- **zsh doesn't split `$var`:** `env $combo` passes one argument, and `(${@:-a b c})` makes one element. Use
  `${=var}` or arrays. RSpec prints "1 example", singular: grep `examples?`.
- **`:inline` runs jobs on the reporting thread:** anything that makes a RED job raise for `retry_on` must be
  tested with the adapter's `enqueue_at` stubbed to raise `NotImplementedError` (tasks/lessons.md).
- **Commit signing goes through 1Password** and can fail after a long hook ("agent returned an error" / "failed
  to fill whole buffer"): HEAD doesn't move, files stay staged; ask the maintainer to unlock or run
  `! git commit -F <file>`. It signed unattended all this session.
- **Chaos failures:** read the kept /tmp/pre_release_test_<pid>/…/log/production.log before deleting anything.
- **Agents and the working tree:** start a reviewer with `isolation: "worktree"`, give it the branch SHA, have it
  read with `git diff <base> <sha>` and `git show <sha>:<path>`, and check `git status`, `git stash list`, the
  reflog and `git worktree list` afterwards.
- **rc.1 baseline for `bin/benchmark`:** the worktree was removed after this session's runs. Recreate it with
  `git worktree add --detach /tmp/red-rc1-bench rails_error_dashboard/v1.0.0-rc.1`; run alternately, two runs
  each, nothing else running.
- In async-in-request mode the server's `response_finished` callbacks run last-first: never assert row order.
  Count `sum(occurrence_count)`, not rows.
- Rules: commit with `LEFTHOOK_EXCLUDE=chaos-tests` only for docs-only commits; write "Refs #N"; one commit per
  task, staged by name; every merge, release, push or setting change needs a yes.
