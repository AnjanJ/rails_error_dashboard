# Design: Audit fixes for 0.16.0

## Approach
Each requirement is a contained fix with a test written first. Most have one obvious fix, and
the table records it. Four have a real choice and get a record below.

| REQ | Fix |
|---|---|
| 1 | `:current_branch` → `Commands::LogError.capture_git_sha` (config, then ENV, then the HEAD detected at boot; no subprocess). Delete `get_current_git_sha` |
| 2 | See the record below |
| 3 | One `RepositoryUrl.normalize` (`strip`, drop trailing `/`s, drop `.git`), used by `GithubLinkGenerator` and `effective_issue_tracker_repo` |
| 4 | See the record below |
| 5 | `MarkdownErrorFormatter` picks frames with `BacktraceParser.parse(raw).select { _1[:category] == :app }` in both sections |
| 6 | `RailsErrorDashboard.resolved_application_name` (config, then ENV, then module name), used by capture, the backfill migration and task, and the three flushers |
| 7 | See the record below |
| 8 | `getComputedStyle(next).display === 'none'` in the layout's `toggle-next` |
| 9 | Coerce with `.to_s.to_sym`; `validate!` rejects anything else |
| 10 | `before_action` returns 404 for a provider outside `PROVIDERS`, ahead of signature checks; drop the two dead branches |
| 11 | Batch commands return `{id => message}` for failures; the flash names them and `Rails.logger.warn` logs them |
| 12 | `BatchMuteErrors` writes the same "Muted notifications: <reason>" comment as `MuteError` |
| 13 | Count only rows whose `show_if` flags are all on |
| 14 | Drop `@mobile_errors` and `@api_errors`, and their two keys in `AnalyticsStats`; update its spec |
| 15-16, 18 | Docs edits, each page with its Jekyll copy; the Devise text also changes in the initializer template |
| 17 | `spec/docs/links_spec.rb` resolves every relative link and anchor; fix the dead anchors and the CONFIGURATION link |
| 19 | `(cd … && exec bin/rails server …) &`, an EXIT trap, and a final `lsof` sweep in `bin/pre-release-test` |

## Decision: bound co-occurring errors to the newest occurrences, in one query   (→ REQ-2)

**Context.** `CoOccurringErrors` runs one window query per lifetime occurrence, plus one
`ErrorLog.find` per result (`co_occurring_errors.rb:42-71`). An error with 50k occurrences means
50k queries on every page render while the feature is on.

**Alternatives.**
1. Take the newest 500 occurrences of the target. Find nearby occurrences of other errors with
   one aggregate SQL query (a self-join on the time window, grouped by `error_log_id`).
   Batch-load the ErrorLogs, and cache with the analytics TTL.
2. One self-join over all occurrences, unbounded.
3. Remove the feature.

**Case for 1.** The query count is constant (REQ-2's test). It keeps #277's precedent for Pattern
Insights (the newest 10,000), and recent co-occurrence is what users act on.

**Case against 1.** Co-occurrences older than the newest 500 events drop out of the panel.

**Decision.** Option 1, with the cap as a constant, not a new option.
**Amended 2026-10-15 (implementation).** The planned cache is not built. With the query count fixed at four, it isn't needed, and it would make the panel stale. The window query is plain `BETWEEN` ranges, so it is the same on SQLite, PostgreSQL and MySQL.
**Falsifiability.** We would make the cap configurable if a user reports the panel missing a
co-occurrence they rely on that lies outside the newest 500 occurrences.
**Fired-if.** manual

## Decision: rate platforms by their share of all errors, and need two to rate   (→ REQ-4)

**Context.** The volume term is `1 - count/max`. So the busiest platform always scores 0 on it,
and at most 30 in total, which is Critical (`platform_comparison.rb:174, 268-276`). A
single-platform app is always Critical.

**Alternatives.**
1. Use `1 - share`, where share = this platform's errors / all errors. With fewer than two
   platforms, show "not rated".
2. Absolute rates (errors per day) against fixed thresholds.
3. Keep the formula and only special-case a single platform.

**Case for 1.** Two equal platforms get equal, non-zero scores. A comparison needs at least two
things to compare. No arbitrary thresholds are introduced.

**Case against 1.** The scores shift for every existing install on upgrade, so the docs' worked
example has to be rewritten (REQ-16 covers that page).

**Decision.** Option 1.
**Falsifiability.** We would move to absolute rates if users report ratings that disagree with
their per-platform error rates after the change.
**Amended 2026-10-15 (implementation).** "Two platforms" means two with errors in the window. The platform list is every platform ever seen, so an old error on a second platform let a lone active platform be rated Critical.
**Amended 2026-10-21 (audit-fixes-0-16-1).** The volume term, `1 - share`, is superseded by "volume credit falls linearly from an even split to all errors" in `.shipkit/specs/audit-fixes-0-16-1/design.md`: with Healthy at 80, no evenly split two- or three-platform app could be Healthy. The "need two to rate" half stands.
**Fired-if.** manual

## Decision: fix the similarity regex everywhere, including the stored signature   (→ REQ-7)

**Context.**
- Three regexes require `` in `…' ``:
  - `similarity_calculator.rb:90`
  - `error_log.rb:344`
  - `BacktraceProcessor.calculate_signature`, which stores `backtrace_signature`
- Ruby 3.4 writes `in 'Class#method'`, so frames there shrink to basenames.
- The signature feeds only "similar errors" (`similar_errors.rb:58-60`), never grouping.

**Alternatives.**
1. Fix all three.
2. Fix the two query-time regexes and leave the stored signature alone.
3. Fix all three and backfill old signatures.

**Case for 1.** Similar-error matching on Ruby 3.4 works from the upgrade on. Grouping is
untouched.

**Case against 1.** On Ruby 3.4 apps, signatures stored before the upgrade (basenames only)
won't match new ones (with method names) until the old rows age out, so "similar errors" briefly
finds fewer matches.

**Decision.** Option 1, with a CHANGELOG note.
**Amended 2026-10-15 (implementation).** The stored `backtrace_signature` keeps only each frame's file name, which the old fallback already produced on Ruby 3.4. So it does not change, the case against above does not occur, and no CHANGELOG note is needed. One `BacktraceProcessor.frame_key` replaces the three regexes. It also drops 3.4's class qualifier, so the same frame gives the same key on either Ruby.
**Falsifiability.** We would add a backfill task if a user reports "similar errors" coming up
empty after upgrading on Ruby 3.4.
**Fired-if.** manual

## Decision: no subprocess for `:current_branch`   (→ REQ-1)

**Context.** The helper runs `` `git rev-parse HEAD` `` with no timeout on every uncached
error-page render (`backtrace_helper.rb:317`). The capture path already removed this pattern
(`git_head_reader.rb:9-14`).

**Alternatives.**
1. Use the commit resolved at boot (`LogError.capture_git_sha`).
2. Keep the subprocess, with `Open3` and a timeout.

**Case for 1.** No fork or exec on a host request thread, which is the host-app safety rule. It
also works on hosts without a `git` binary, and it matches the capture path.

**Case against 1.** A checkout that changes branch without restarting the app links to the
commit it booted on.

**Decision.** Option 1.
**Falsifiability.** We would reconsider if a user needs links to follow branch changes without a
restart.
**Fired-if.** manual
