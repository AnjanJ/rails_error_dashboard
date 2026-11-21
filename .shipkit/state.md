# Handoff

> Written 2026-11-21 on feat/hardening-grouping-window (PR 3: T7 and T8), after `f1e39d73`; this note is
> the branch's last commit. The branch is not pushed yet. Pushing and opening the PR need the
> maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T8 and T35 are done. PR 1 (#373) and PR 2 (#375) are squash-merged, and
  PR 2's branch is deleted. PR 3 is this branch, waiting for the maintainer's yes to push and open it.
  T9-T34 are unstarted.
- The tracking issue is #374. Items 1 and 2 of its checklist are ticked. Tick item 3, adding "(#N)",
  when PR 3 merges. Change only that line, and diff the body before saving. Never close it.

## Done this session (2026-11-21)
- `7b960efc` T7 (REQ-9 to REQ-11): an open group is matched by its last occurrence.
  `FindOrIncrementError.within_group_window` (`last_seen_at > :cutoff OR (last_seen_at IS NULL AND
  occurred_at > :cutoff)`) serves find_unresolved, its duplicate-create retry (which now calls
  find_unresolved) and `FlushStormCounts#unresolved_target`, and it wraps `with_hash` / `with_hashes`,
  so it applies to v2 and v1.
  - design.md said `>=`. REQ-10 starts a new group at "24 hours old or more", so the record was
    amended to `>` in the same commit. This still needs the maintainer's yes.
  - `spec/commands/grouping_window_spec.rb`: 30 examples (5 window cases x v2/v1 x lookup, retry,
    flush). 6 fail on main's code. Seven deliberate breaks each fail 2-6 examples. With no NULL
    fallback, only the v1 examples fail: in v2 the new row collides on the group-identity index and
    `claim_conflicting_row` counts it on the seeded row.
  - `benchmark/scenarios.rb` "Reopen collision fallback" seeded its stale open row with
    `last_seen_at` = now, so the new rule found it and never collided (full-suite failure at
    `spec/benchmark/scenarios_spec.rb:185`). It now seeds `last_seen_at` two days ago and rolls back
    each iteration. Without the rollback, 1 claim instead of 4.
  - EXPLAIN on PostgreSQL 16, 200,000 rows: the lookup uses
    `index_rails_error_dashboard_error_logs_on_error_hash` (rc.1 used
    `index_error_logs_on_hash_resolved_occurred`); 0.116 ms against 0.097. The decision's reversal
    condition did not fire.
  - bin/benchmark against rc.1 (M3 Max, SQLite, YJIT, alternating, two runs each): storm check calm
    3.43-3.44 vs 3.31-3.46 us, shedding 4.66-4.70 vs 4.61-4.76, open 4.53-4.61 vs 4.42-4.69; async
    capture 99 vs 99-106 us; sync capture 0.995-1.04 vs 1.03-1.10 ms. The reopen row (892-895 vs
    948-971 us) is not like for like, since the scenario changed. Put these in PR 3's body.
- `f1e39d73` T8 (REQ-12): PLUGIN_SYSTEM.md (:54 and the Jira example), GLOSSARY.md, API_REFERENCE.md
  and TROUBLESHOOTING.md describe the last-occurrence rule, and so do their Jekyll copies in
  `_features/` and `_reference/`.
- The shipkit reviewer (worktree): PASS, with REQ-9 to REQ-12 MET. It listed `benchmark/scenarios.rb`
  and the Jekyll copies as beyond the spec's paths, and both were explained above. Its worktree was
  created at main, not at the branch: point a reviewer at the branch SHA with `git show <sha>:<path>`.
- Full suite at `7b960efc`'s tree: 7,231 examples, 0 failures, 9 pending. Lefthook at `7b960efc`:
  chaos 1,742 passed, 0 failed. spec-check: 0 gaps.

## Next step
1. The maintainer decides on the `>` amendment, the push, and opening PR 3. Then watch CI, especially
   the PostgreSQL, MySQL and Ruby 3.3 jobs, and the benchmark job's CPU row.

## Open questions
- `docs/TROUBLESHOOTING.md:312` (and `_reference/troubleshooting.md`) still describes the v1 recipe
  ("the file of the first backtrace line"). PR 2 changed the recipe. This is outside T7 and T8 and is
  not fixed.
- Release-please opened #376 "release 1.1.0-rc.1", its default bump after a `feat:` commit. tasks.md
  plans rc.2 through a `Release-As: 1.0.0-rc.2` commit, so #376 must not be merged as it is.
- Not changed, recorded in design.md: the in-process notification throttle is keyed by the hash, so a
  group moved to v2 can send one extra notification.

## Do not forget
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
