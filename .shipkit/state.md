# Handoff

> Written 2026-11-20 on spec/hardening-1-0-rc2, after `d5a8317b`; this note is the branch's last commit.

## In flight
- **`hardening-1-0-rc2`**: T1 is done, committed (`d5a8317b`) and pushed. T2-T31 are unstarted. The maintainer accepted option 2 (captures wait for the host's transaction, on the shared connection), kept `isolate_capture_writes` and `capture_connection_timeout`, and accepted reading-role writes going to the writing database (stated in `CONFIGURATION.md` by T30) and the private `connection_lease` with its fallback.
- No PR is open for `spec/hardening-1-0-rc2`.

## Done this session
- `7d055cad`: the handoff. The branch is pushed, and dotfiles' `fix/drop-stale-rails-version` is deleted.
- `d5a8317b`: spike S1's research (`.shipkit/research/host-conditions-spike.md`) and the amendment (REQ-17, 18 and 20 amended; REQ-51 to 53 new; T30 rewritten). spec-check: 0 gaps.
- Cleaned up: the 11 throwaway databases are dropped, `/tmp/red-s1` is deleted, and the MySQL 8.4 server is stopped.

## Next step
T2, spike S2 (`tasks.md` T2): every `Logger.error` call site and what it prints, a 60 s storm against a broken schema, and one `Rails.logger.error` call's cost to a file and to STDOUT. Write `.shipkit/research/silent-failures-spike.md`, then stop for the maintainer.

## Open questions
- Pushing new work needs a yes each time.
- The maintainer picks S2's option before any change to `log_level`. Host safety comes first.
- A tracking issue for the sprint: ask, with its text, before T3's first code PR.

## Do not forget
- MySQL 8.4 for T30: `mysql@8.4` is installed (keg-only), but its data was deleted. Start a throwaway server like this:
  1. `/opt/homebrew/opt/mysql@8.4/bin/mysqld --no-defaults --initialize-insecure --datadir=<dir> --basedir=/opt/homebrew/opt/mysql@8.4`
  2. Run `mysqld` with `--port=3307 --bind-address=127.0.0.1 --mysqlx=OFF` and its own socket and pid file.

  Never touch the 26.10 service on 3306.
- Run probes on their own bundle: a Gemfile that does `eval_gemfile "<repo>/Gemfile"`, with `BUNDLE_GEMFILE` and `RAILS_VERSION` set. The repo's `Gemfile.lock` then stays on Rails 8.1.4.1.
- `Rails.error.report(e)` alone is skipped by RED (a handled warning, `error_reporter.rb:25`). Probes need `severity: :error`.
- Phase G exists, so the new chaos phase is `phase_q`. The PostgreSQL and MySQL adapter jobs run Rails 8.1 only (`test.yml:104`).
- Rules: commit with `LEFTHOOK_EXCLUDE=chaos-tests` only for docs-only commits; write "Refs #N"; one commit per task, staged by name; every merge, release, push or setting change needs a yes.
