# Intake: bring the storm check back under its budget

> Intake taken on 2026-10-30.

## Request
The overhead benchmark (spec `overhead-benchmark`, T3) measured the storm check on an Apple M3 Max
(Ruby 3.4.5, Rails 8.1.4), batched, 100 calls per sample:

| State | Median | Budget |
|---|---|---|
| Calm | 6.41 µs | < 5 µs |
| Breaker open | 8.81 µs | < 5 µs |

The README quotes 2.4 µs. The maintainer chose (2026-10-30) to make the gate cheaper before the
benchmark's CI gate lands, rather than land it red or raise the budget.

## Serves goal
"Prove the overhead budget: … storm check < 5µs" (`.shipkit/product.md`). The benchmark is also the
1.0 launch headline (decision 0002).

## What the measurements show (probes on 2026-10-30, same machine)
- **Most of the cost is `Gate.gate_parts`: 5.45 µs of the 6.47.** Stack depth makes no difference:
  about 5.9 µs at 4, 14, 64 and 204 frames.

  | Inside `gate_parts` | Cost |
  |---|---|
  | `opaque_identity` digest | 1.75 µs |
  | `EncodingSanitizer.scrub_deep` over nine values | 1.42 µs |
  | `normalize_message` | 1.21 µs |
  | `redact` | 0.69 µs |
  | `extract_app_frame_from_locations` | 0.26 µs, computed twice |

- **Most of that work is thrown away.** The parts other than the key (the redacted and scrubbed
  message, the frame, the names) are read only when a fingerprint first enters the count buffer
  (`count_buffer.rb:166`, `compute_if_absent`). On the calm path, and for every later event of a
  known fingerprint, only the gate key is used.
- **A key-only path, timed:** calm 3.10 µs (the key alone is 2.62). Open 5.31 µs, of which
  `CountBuffer#record` for a known key is 1.71 µs. It calls `Time.current` and builds a one-entry
  hash on every event.
- **The flush job never reads the gate key.** It rebuilds the canonical hash from the stored parts
  (`flush_storm_counts.rb`), and buffered times leave as ISO 8601 instants.

## Result (T3, 2026-10-30)
`bin/benchmark` on the machine of record (Apple M3 Max, 14 CPUs, Ruby 3.4.5, Rails 8.1.4, SQLite),
storm rows batched 100 calls per sample, median of 5 round medians:

| Row | Before | After | Budget |
|---|---|---|---|
| Storm check, calm | 6.41 µs | 3.39 µs | < 5 µs, PASS |
| Storm check, breaker open | 8.81 µs | 4.57 µs | < 5 µs, PASS |

The other gated rows didn't move: capture 112 µs, breadcrumb 0.63 µs, health 14.0 µs. The open
row has about 0.4 µs of headroom here. The CI runner's numbers come with the benchmark's CI job
(`overhead-benchmark` T4).

## Conflicts found
- **Paramount: the gate runs on the request thread and must fail open.** Every change keeps the
  existing rescue: any error gives `:full`.
- **0.17.0's capture hardening:** a message is redacted and scrubbed before it's buffered, so a
  secret never reaches the queue's store. Building the exemplar lazily must keep that: whatever is
  buffered is built exactly as today.
- **Thread safety by construction** (the gate's own comment): no shared mutable caches on the hot
  path. The lazy exemplar is a per-call local, not a cache.
- **Open specs:** `overhead-benchmark` measures this. Its T4 (the CI gate) and T5 (README numbers)
  wait for this spec.

## Answers
1. **Make the gate cheaper first** (2026-10-30), instead of landing the CI gate red or raising the
   budget.

## Assumptions made
- **The gate key's format stays as it is.** Dropping its second SHA-256 would save about 0.4 µs, but
  keys also appear in snapshots restored after a failed handoff. That isn't worth the risk now.
- **The identity stays SHA-256 over the same normalised inputs,** because it must match what the
  sync and async paths compute.
- **The CI runner may be slower than the M3 Max.** The first CI run of the benchmark sets the real
  target. If 5 µs isn't met there after this change, the next step comes back to the maintainer.

## Out of scope
- Changing what the gate decides, the thresholds or the budget.
- The capture path after the gate.
