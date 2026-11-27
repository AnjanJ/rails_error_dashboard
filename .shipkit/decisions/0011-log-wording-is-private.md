# 0011: The wording of RED's log lines is private, except the prefix of a failed capture's line

- **Date:** 2026-11-27. Status: accepted (the maintainer said yes on 2026-11-27, in PR 11; drafted from
  `hardening-1-0-rc2`, T33).

## Context

`docs/PUBLIC_API.md` says what 1.x keeps stable, and anything it doesn't name is private. It said nothing
about log lines. PR 11 (T33) rewrote every line a failed capture writes: rc.1's lines carried messages and
context, and rc.2's summary line carries only classes, rate-limited. A host that greps or alerts on RED's
log text has nothing to rely on, and RED can't reword a line without wondering who it breaks.

## Alternatives

1. Every line's wording is private, except the summary line's prefix,
   `[RailsErrorDashboard] Capture failure in`, which stays for all of 1.x.
2. Every line's wording is private, with no exception.
3. Freeze the wording of every line RED writes.

## Case for 1

- The one line worth alerting on is the one that says a capture was lost, and its prefix is enough to
  match it. Hosts get one stable hook, and RED stays free to reword everything else, the detail at debug
  included.
- The promise is small enough to test: `spec/services/capture_failure_log_spec.rb` checks the prefix.

## Case against 1

- A host that matches more than the prefix, such as the site names or the suppressed count, can still
  break on a minor release.
- The prefix ties 1.x to the word "Capture" even for lines from the storm flush job and RED's own job
  retries, which aren't captures in the user's sense.

## Decision

1. `docs/PUBLIC_API.md` lists the wording of RED's log lines under "What's private", except that prefix.

**I would reverse this if** two or more issues in 1.x ask for a stable field of the failure line beyond the
prefix (then freeze that field in a minor, as an addition, and test it).
**Fired-if.** manual
