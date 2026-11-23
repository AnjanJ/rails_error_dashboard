# Handoff

> Written 2026-11-23 on feat/hardening-notifications (PR 5: T14-T16), after `f4c16092`; this note is the
> branch's last commit. Nothing is pushed. The push, opening the PR, each later push and the merge each need
> the maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T16, T32 and T35 are done. PRs 1-4 (#373, #375, #377, #378) are squash-merged
  and their branches deleted. PR 5 is this branch, not yet pushed. T17-T31, T33 and T34 are unstarted.
- The tracking issue is #374. Items 1-4 of its checklist are ticked. Tick item 5, adding "(#N)", when PR 5
  merges. Change only that line, diff the body before saving, and never close it.

## Done this session (2026-11-23)
- PR 5, each task test-first, with deliberate breaks, the full suite and the full lefthook (chaos 1,742 passed):
  - `c433eb55` T14 (REQ-29 to REQ-31): the six channel jobs raise `TransientDeliveryError` on a timeout, a
    refused or reset connection, DNS, HTTP 429/5xx or SMTP 4xx (new `Concerns::TransientDelivery`), and
    retry 3 times; anything else logs and finishes. When retries run out the job calls
    `NotificationThrottler.release!`, which clears `last_notified_at` only if it still equals the job's
    `claimed_at` (LogError picks the time, passes it to `claim!(at:)` and the dispatcher). A nanosecond
    claim time matches the stored microseconds on SQLite and PostgreSQL 16 (reproduced). 43 breaks.
  - The first T14 commit's chaos run caught a host-safety bug in it: on `:inline` (and Resque without a
    scheduler, Sneakers, queue_classic) `enqueue_at` raises `NotImplementedError`, a ScriptError that
    passed every rescue on the capture path and reached the host. The concern now overrides `retry_job`:
    a retry that can't be scheduled is the last attempt. Recorded in design.md and tasks/lessons.md.
  - `484fe0bd` T15 (REQ-32, REQ-33): one webhook job per URL, given `WebhookDelivery.url_digest(url)`, not
    the URL (tokens; maintainer's yes, in design.md). `X-Error-Dashboard-Delivery` is a SHA-256 of
    `job_id` and the URL, so it survives retries; posts with no job get a random id. WEBHOOKS.md has
    "Delivery: at least once"; NOTIFICATIONS.md lists the header (maintainer's yes). 11 breaks.
  - `f4c16092` T16 (REQ-34, REQ-35): `CreateIssue` returns `code:` (`:created`, `:already_linked`,
    `:not_configured`, `:not_found`, `:failed`; the last two beyond design.md's three, with the
    maintainer's yes). The job counts a failed result once and doesn't retry the first three failure
    codes. The task's `I18n.with_locale(:de)` alone can't make the test fail: `red_t` follows
    `dashboard_locale`, so the test sets both and checks the text is German. 11 breaks.
- Full suite at `f4c16092`: 7,347 examples, 0 failures, 9 pending. The shipkit reviewer: PASS, 7 MET
  (REQ-29 to REQ-35). spec-check: 0 gaps.
- No bin/benchmark: the request path does no new work in T14 (`Time.current` moved from `claim!` to its
  caller) and the benchmark configures no channels; with webhooks on, a sync capture now enqueues one job
  per URL instead of one. Read, not measured.

## Next step
1. The maintainer decides on pushing this branch and opening PR 5. Its body needs the points above,
   "Refs #374" and the Claude Code line.

## Open questions
- One intermittent chaos failure on this branch, not explained: the sync app failed E0 (the subscriber
  probe) once during T14's second commit attempt, then passed 8 runs in a row and both later commits. The
  failed app was deleted before its log was read. Watch for E0 on CI.
- `_guides/notifications.md` lacks the "Muting Notifications for Specific Errors" section that
  `docs/guides/NOTIFICATIONS.md` has (pre-existing, not changed).
- `CreateIssueJob`'s `discard_on`/`rescue ActiveRecord::RecordNotFound` is still unreachable (the command
  rescues it); `:not_found` now covers the case. Removing them is a separate cleanup.
- The installer template's sync comment says "adds ~1-5ms to requests that trigger errors"
  (`templates/initializer.rb`), against the measured 3.23-16.38 ms. T34 (REQ-61) edits that template; fix it
  there.
- Release-please's #376 ("release 1.1.0-rc.1") must not be merged as it is: rc.2 is cut with a
  `Release-As: 1.0.0-rc.2` commit (tasks.md, the release steps). The rc.2 notes must say a manual `gem push`
  needs MFA, and should say notifications now retry (receivers can see duplicates; the delivery header).
- The Upgrade Path job runs only on release PRs and PRs touching migrations, so a grouping regression can
  reach main unseen (#375's did). Worth a CI change; needs the maintainer's yes.
- Not changed, recorded in design.md: the in-process notification throttle is keyed by the hash, so a group
  moved to v2 can send one extra notification.

## Do not forget
- **Commit signing can also time out.** After a ~4 minute lefthook run, 1Password failed with `failed to fill
  whole buffer` (no unlock prompt answered in time). The maintainer ran `! git commit -F <msg>` themselves and
  approved the prompt; later commits signed unattended.
- **Chaos failures:** the orchestrator keeps `/tmp/pre_release_test_<pid>` on failure. Read the app's
  `log/production.log` before deleting it; reruns in it fail after phase Z drops the tables. Reproduce with
  `bin/pre-release-test full_sync` (about a minute) instead.
- **Retry tests:** stub the adapter's `enqueue_at` to raise `NotImplementedError` to test an adapter that
  can't schedule; never swap adapters. `CreateIssue`'s messages follow `dashboard_locale`, not `I18n.locale`.
- **Commit signing goes through the 1Password agent too.** A locked 1Password fails a commit *after*
  lefthook has run (`error: 1Password: agent returned an error`, `fatal: failed to write commit object`);
  HEAD doesn't move and the files stay staged. Ask the maintainer to unlock it, then rerun the commit.
- **SQLite and bigint:** a SQLite bigint column reports `limit` nil, and Rails' `SQLite3Integer` holds 8 bytes
  for every integer column. Tell bigint apart by `sql_type`, not `limit`.
- **The upgrade test depends on where the checkout lives.** J0-J8 raise errors in the gem's own chaos scripts,
  so a checkout under /tmp gives other frames than a normal one: J7 then takes its "regrouped" branch and
  passes where CI fails. Bisect `full_upgrade` from a worktree beside the repo, never under /tmp.
- **The reviewer's worktree starts at main,** not at the branch. Give it the branch SHA and have it read with
  `git diff <base> <sha>` and `git show <sha>:<path>`.
- **Agents and the working tree:** start a reviewer or research agent with `isolation: "worktree"`, and tell it
  not to checkout, stash or reset. The first T3 reviewer, started without it, stashed the uncommitted T4 work
  and checked out a past commit in this tree. It restored everything, but check `git status`, `git stash list`
  and the reflog after any agent.
- **Storm specs and entries:** a hand-built storm entry without `opaque_identity` and `opaque_identity_v1` has
  rc.1's shape and is counted under v1 alone (REQ-6), so it can't reach a group sync created since T4. Give such
  entries the gate's identity with `StormEntryIdentity.for(error, context)` (`spec/support/storm_entry_identity.rb`).
- **The benchmark's exception** is raised by one-line recursion (`benchmark/scenarios.rb:233`), so REQ-2's
  same-line rule walks all 63 frames. The gate no longer runs that walk per event (it keys on
  `ErrorHashGenerator.gate_source`); anything added to `gate_source` is paid on every storm check, and CI's
  slowest runner (AMD EPYC 7763) has under 4.5 µs of headroom there.
- **rc.1 baseline for `bin/benchmark`:** the worktree used for PR 2 was removed. Recreate it with
  `git worktree add --detach /tmp/red-rc1-bench rails_error_dashboard/v1.0.0-rc.1`, then run the benchmark there
  and in the repo alternately, two runs each, with nothing else running (a busy machine moved medians by over
  1 µs). Remove it with `git worktree remove /tmp/red-rc1-bench`. On CI, rc.1's storm-check medians by runner:
  EPYC 7763 (`a1539361`) calm 8.21, shedding 10.85, open 10.59 µs; Xeon 6973P-C (`9b43b1ea`) 5.26, 7.52, 6.77 µs.
- MySQL 8.4 for T30: `mysql@8.4` is installed (keg-only), with no data. Start a throwaway server like this:
  1. `/opt/homebrew/opt/mysql@8.4/bin/mysqld --no-defaults --initialize-insecure --datadir=<dir> --basedir=/opt/homebrew/opt/mysql@8.4`
  2. Run `mysqld` with `--port=3307 --bind-address=127.0.0.1 --mysqlx=OFF` and its own socket and pid file.

  Never touch the 26.10 service on 3306.
- Run probes on their own bundle: a Gemfile that does `eval_gemfile "<repo>/Gemfile"`, with `BUNDLE_GEMFILE` and
  `RAILS_VERSION` set. The repo's `Gemfile.lock` then stays on Rails 8.1.4.1.
- `Rails.error.report(e)` alone is skipped by RED (a handled warning, `error_reporter.rb:25`). Probes need
  `severity: :error`.
- **Timing on macOS:** `CLOCK_MONOTONIC` resolves only 1 µs there. Time single calls with `CLOCK_MONOTONIC_RAW`
  (42 ns), or amortise over many calls.
- **Solid Queue on SQLite under Rails 7.2:** with a worker and a dispatcher in one process, the dispatcher thread
  can die on `SQLite3::BusyException`. It happened in 1 of 2 runs alone. Scheduled retries then never run, so a
  probe that waits for an empty queue hangs until its timeout.
- **Logging tests (T32, T33):** a new Rails app logs Active Job arguments at `info`, and spec/dummy has no
  `filter_parameter_logging.rb`. Set the template's `filter_parameters` in the test, or Rails' own lines will
  show the raw params and hide what RED does.
- Phase G exists, so the new chaos phase is `phase_q`. The PostgreSQL and MySQL adapter jobs run Rails 8.1 only
  (`test.yml:104`).
- Rules: commit with `LEFTHOOK_EXCLUDE=chaos-tests` only for docs-only commits; write "Refs #N"; one commit per
  task, staged by name; every merge, release, push or setting change needs a yes.
