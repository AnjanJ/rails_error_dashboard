# Handoff

> Written 2026-11-20 on spec/hardening-1-0-rc2, after `60f5aef5`; this note is the branch's last commit.

## In flight
- **`hardening-1-0-rc2`**: T1 and T2 are done and committed. T1 is pushed; T2 (`60f5aef5`) and this handoff are
  **not pushed**. T3-T34 are unstarted.
- **What S2 settled** (accepted 2026-11-20, all six follow-ups "yes"): option 2, a trimmed line per call site and
  failure class a minute, with default `log_level :error`. It became REQ-54 to REQ-61 and tasks T32-T34:
  - **T32** ships in PR 4. It stops the failure lines printing raw params and the URL, and sets
    `log_arguments = false` on the capture and flush jobs.
  - **T33-T34** are a new PR 11.
  - **Not in rc.2:** the `/health` failure count. The 16 dashboard-only sites are unchanged.
- No PR is open for `spec/hardening-1-0-rc2`.

## Done this session
- `60f5aef5`: spike S2's research (`.shipkit/research/silent-failures-spike.md`) and the amendment.
  - `spec.md`: "Capture failures" with REQ-54 to REQ-61, a user story, and the S2 spike marked done.
  - `design.md`: the S2 outcome, a decision record and the interface changes.
  - `tasks.md`: T32 (After T13), T33 (After T7, T30, T32), T34 (After T33). T30's After gains T32.
    Eleven PRs now.
  - spec-check: 0 gaps.
- Cleaned up: the 6 throwaway databases are dropped, `/tmp/red-s2` is deleted, and the MySQL 8.4 server on 3307
  is stopped. The 3306 service was not touched.

## Next step
Ask the maintainer two things, each with a yes before acting:
1. Push `spec/hardening-1-0-rc2` (T2 and this handoff), then open PR 1 for the spikes (T1-T2). The branch also
   holds the spec and the handoffs.
2. Before T3: open a public tracking issue for the sprint, so commits can say `Refs #N`. Show its text first, with
   no reproduction details. The sync failure line's password leak (T32) counts as a reproduction detail.

Then T3 (grouping v2), test first.

## Open questions
- Pushing needs a yes each time.
- T32 fixes a defect any host at `log_level :error` has today. The issue and release notes must describe it
  without a recipe.

## Do not forget
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
