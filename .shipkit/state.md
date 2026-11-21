# Handoff

> Written 2026-11-21 on feat/hardening-grouping-v2 (PR 2: T3-T6 and T35), after `aabe535a`; this note is the
> branch's last commit. The branch is pushed as PR #375, with CI green. Merging needs the maintainer's yes.

## In flight
- **`hardening-1-0-rc2`**: T1-T6 and T35 are done. PR 2 is #375, CI green at `aabe535a`, waiting for the
  maintainer's merge. T7-T34 are unstarted.
- **PR 1 (#373)** is merged. The tracking issue is #374: tick its checklist as each PR merges; never close it.

## Done this session (2026-11-21)
- `f7bd8fb5` T3: `ErrorHashGenerator.identities` and the v2 recipe (REQ-1 to REQ-4, REQ-7). `5945a98f` ticks it.
- `58e87a44` T4 and T5 together, with the maintainer's yes: sync, async, the storm gate, the buffer and the flush
  carry v2 and v1, the lookups match `error_hash IN (v2, v1)` preferring v2, and a v1 row moves to v2 in a
  savepoint (REQ-5, REQ-6, REQ-7). T4 alone failed 15 storm specs, which is why they landed together.
  - The first benchmark failed the storm check (19-20 µs against 15 µs). The cause was T3's frame walk
    (`Enumerator::Lazy`, a label per frame) on the benchmark's 63-frame one-line recursion, which REQ-2's
    same-line rule walks to the end. Rewritten as a plain loop, same rule: v2_identity 17.07 → 2.36 µs.
  - Benchmark medians, rc.1 → branch, same machine (M3 Max, SQLite, YJIT), two alternating runs each: storm
    check calm 3.15-3.18 → 4.73-4.76 µs, shedding 4.36-4.39 → 5.90-6.23 µs, breaker open 4.24 → 5.69-5.85 µs;
    async capture 92-93 → 97-98 µs; sync capture 888-905 → 937-939 µs. Put these in PR 2's body.
- `301029c8` amendment, with the maintainer's yes: REQ-62 and T35 (a new v2 group links to its v1 group's
  issue; `issue_tracker_subscriber.rb:71-76` matched by `error_hash` alone). T7 and T11 now come after T35.
- `8ece1185` T35 (REQ-62). `cb489217` T6: `docs/PUBLIC_API.md` "Grouping" and decision 0010 (REQ-8);
  `bad8a8d7` says groups are per application and environment.
- The shipkit reviewer, now run per task with the maintainer's yes: PASS for T3 (REQ-1 to REQ-4, REQ-7) and
  for T4+T5 (REQ-5 to REQ-7), and for T35 and T6 (REQ-62, REQ-8). The last noted that the page left out the
  per-application scope; `bad8a8d7` adds it.
- Full suite at `27591bdb`: 7,201 examples, 0 failures, 9 pending. spec-check: 0 gaps.

## After the PR opened (2026-11-21)
- CI's first run failed 4 jobs, all on test preconditions; `10ef15ea` fixed them:
  - Ruby 3.3 writes `` `nme' ``, which the normaliser doesn't fold, so the REQ-4 example's "same message"
    precondition failed (v1 never merged those names on 3.3);
  - MySQL has no partial indexes, so the group-identity index doesn't exist and the move can't collide.
- Then the benchmark job failed: storm check 14.68-15.47 µs on the AMD EPYC 7763 runner (budget 15 µs; rc.1
  10.59-10.85 µs there). design.md's gate record fired; with the maintainer's yes it was amended (`bcbb3811`)
  and fixed (`27591bdb`): the gate keys events on `ErrorHashGenerator.gate_source` (first kept frame's
  path:line, no same-line walk) and computes v2 and v1 once per new buffer entry. T5 was reopened and
  re-ticked.
  - Local storm medians now equal rc.1's (calm 3.11-3.23 vs 3.21-3.22 µs; shedding 4.37-4.39 vs 4.46-4.49;
    open 4.20-4.23 vs 4.28-4.45). p95 is about 0.7 µs higher.
  - CI at `27591bdb` ran on an Intel Xeon 6975P-C: calm 5.28, shedding 6.97, open 6.85 µs (rc.1 era on a
    Xeon 6973P-C: 5.26, 7.52, 6.77).
  - CI at `aabe535a` ran on the AMD EPYC 7763, the runner type that failed: calm 7.99, shedding 11.21, open
    10.95 µs, against rc.1's 8.21, 10.85 and 10.59 µs there. About 4 µs under the budget.

## Next step
1. The maintainer decides on merging #375 (squash; deleting the branch needs its own yes).
2. After PR 2 merges: tick #374, branch from main for PR 3 (T7-T8, the grouping window). T7's lookups are now
   `with_hash` / `with_hashes`, and its window change must apply to both hashes.

## Open questions
- None from this session. Each push, PR, merge or branch deletion still needs its own yes.
- Not changed, recorded in design.md: the in-process notification throttle is keyed by the hash, so a group
  moved to v2 can send one extra notification.

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
