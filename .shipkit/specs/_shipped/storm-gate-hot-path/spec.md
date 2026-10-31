# Spec: Bring the storm check back under its budget

> Spec accepted at commit `5a1fee6` on spec/0-18-0 (2026-10-30).
> Status: shipped in 0.18.0 (#335)
> Paths: lib/rails_error_dashboard/services/storm_protection/gate.rb,lib/rails_error_dashboard/services/storm_protection/count_buffer.rb,spec/services/storm_protection/

## Purpose
The storm check runs on the request thread for every error, and its documented budget is 5 µs.
Measured, it costs 6.4 µs with the breaker calm and 8.8 µs with it open. Most of that is building a
redacted copy of the error that is thrown away almost every time: it's only kept when a fingerprint
first enters the count buffer. This spec makes the gate build only what each event needs, without
changing anything the gate decides or stores.

## User stories
- As a developer whose app is having a bad day, I want RED's per-error check to stay within its
  published budget, so that RED doesn't add to the outage.
- As the maintainer, I want the 1.0 benchmark to show the storm check within budget, with numbers
  anyone can reproduce.

## Requirements (EARS)

### Only what each event needs
- **REQ-1.** When the storm gate handles an error, it shall build the redacted exemplar only if the
  count buffer is about to store a new entry for that error's key. The exemplar is the redacted,
  scrubbed message, the first app frame, the names, the custom hash, the environment and the
  capture source.
- **REQ-2.** When the count buffer stores a new entry, the entry shall be identical, field for field,
  to what 0.17.0 stores for the same error and context. In particular, the message is redacted and
  scrubbed before it's buffered.
- **REQ-3.** For any sequence of errors and contexts, the gate shall return the same decisions
  (`:full`, `:lite`, `:count_only`) and the same gate keys as in 0.17.0.
- **REQ-4.** When the count buffer counts an event for a key it already holds, it shall do so without
  building a time-zone-aware timestamp or any per-event hash. Its counts, per-bucket tallies, and
  first- and last-seen times stay as in 0.17.0.

### Safety
- **REQ-5.** If anything in the gate raises, the gate shall return `:full`, as today.

### The budget
- **REQ-6.** `bin/benchmark`'s two storm-check rows shall pass their 5 µs budget on the machine of
  record (the maintainer's Apple M3 Max). The CI runner's numbers are reported in the PR. If they
  miss the budget, the next step goes back to the maintainer.

## Out of scope
- What the gate decides, its thresholds, and the budget itself.
- The gate key's format and the identity digest.
