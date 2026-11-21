# Handoff

> Written 2026-11-21 on feat/hardening-defaults-hygiene (PR 4: T9-T13 and T32), after `e40d8a4a`; this
> note is the branch's last commit. The branch is not pushed. Pushing, opening the PR and merging each
> need the maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T13, T32 and T35 are done. PRs 1-3 (#373, #375, #377) are squash-merged and
  their branches deleted. PR 4 is this branch. T14-T31, T33 and T34 are unstarted.
- The tracking issue is #374. Items 1-3 of its checklist are ticked. Tick item 4, adding "(#N)", when PR 4
  merges. Change only that line, diff the body before saving, and never close it.

## Done this session (2026-11-21)
- PR 3 (#377, T7-T8) merged as `6bcabbdd`, #374 item 3 ticked, branch deleted, all with the maintainer's yes.
- PR 4, each task test-first, with deliberate breaks, the full suite and the full lefthook (chaos 1,742 passed):
  - `7df7a856` T9 (REQ-13): the docs say async is the installer's default and sync the library's, and give
    sync's cost: 3.23-6.78 ms with the database on the runner, 11.84-16.38 ms with it 1 ms away. FAQ.md is
    outside T9's list: its "~10-50ms" / "~1-2ms" figures contradicted the measurements.
  - `f2778d3b` T10 (REQ-14): `rubygems_mfa_required`. The release uses trusted publishing, which rubygems.org
    doesn't hold to the flag (design.md, REQ-14 notes). The rc.2 notes must say a manual `gem push` needs MFA.
  - `13145864` T11 (REQ-15): an out-of-range `user_id` is stored as nil. Before, `create!` raised
    `ActiveModel::RangeError` and the whole capture was lost. The occurrence is checked against its own column.
  - `0471cf85` T12 (REQ-16): fresh installs create `user_id` as bigint; UPGRADING.md has "Widen `user_id` to
    bigint". CONFIGURATION.md and API_REFERENCE.md updated to match.
  - `bf877987` T13 (REQ-21): a `ConnectionTimeoutError` in the application lookup skips the fallback.
  - `e40d8a4a` T32 (REQ-59, REQ-60): no Context lines on the failure paths; `log_arguments = false` on the two
    capture jobs; an exhausted job is named by class and id. The spec passes on Rails 7.2.4, 8.0.5.2, 8.1.4.1.
- bin/benchmark against rc.1 (M3 Max, SQLite, YJIT, alternating, two runs each): sync capture 1.02-1.04 vs
  1.06-1.12 ms; async 95-100 vs 103 µs; storm check calm 3.38-3.41 vs 3.39-3.59 µs, shedding 4.59-4.63 vs
  4.71-5.17, open 4.44-4.62 vs 4.50-4.83. Put these in PR 4's body.
- Full suite at `e40d8a4a`: 7,250 examples, 0 failures, 9 pending. The shipkit reviewer: PASS, 7 MET (REQ-13
  to REQ-16, REQ-21, REQ-59, REQ-60). spec-check: 0 gaps.

## Next step
1. The maintainer decides on pushing and opening PR 4. Then watch CI, especially the PostgreSQL and MySQL jobs
   (T11's range check and T12's bigint run against real 4-byte columns there) and the Rails 7.2 and 8.0 rows.

## Open questions
- The installer template's sync comment says "adds ~1-5ms to requests that trigger errors"
  (`templates/initializer.rb`), against the measured 3.23-16.38 ms. T34 (REQ-61) edits that template; fix it
  there.
- Release-please's #376 ("release 1.1.0-rc.1") must not be merged as it is: rc.2 is cut with a
  `Release-As: 1.0.0-rc.2` commit (tasks.md, the release steps).
- Not changed, recorded in design.md: the in-process notification throttle is keyed by the hash, so a group
  moved to v2 can send one extra notification.

## Do not forget
- **Commit signing goes through the 1Password agent too.** A locked 1Password fails a commit *after*
  lefthook has run (`error: 1Password: agent returned an error`, `fatal: failed to write commit object`);
  HEAD doesn't move and the files stay staged. Ask the maintainer to unlock it, then rerun the commit.
- **SQLite and bigint:** a SQLite bigint column reports `limit` nil, and Rails' `SQLite3Integer` holds 8 bytes
  for every integer column. Tell bigint apart by `sql_type`, not `limit`.
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
