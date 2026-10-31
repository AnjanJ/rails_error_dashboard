# Design: Bring the storm check back under its budget

## Approach
- **The gate splits "who is this error" from "what would we keep of it".**
  - `gate_identity(exception, context)` computes, once per event:
    - the raw message prefix;
    - the app frame (looked up once, not twice as today);
    - the custom hash (the user's fingerprint lambda, called once);
    - the scrubbed environment;
    - the opaque identity digest.
  - `gate_key_for(identity)` makes the same 16-character key as today:
    `SHA256("#{custom_hash || opaque_identity}|#{environment}")[0..15]`.
  - `exemplar(identity, exception, context)` builds exactly the hash `gate_parts` builds today,
    redaction and `scrub_deep` included, from the identity already computed.
  - `gate_parts` becomes `exemplar(gate_identity(...))`. It's kept for the reference tests.
- **`decide` uses only the key.** Where it counts an event, it passes the exemplar as a block:
  `count_buffer.record(key) { exemplar(identity, exception, context) }`.
- **`CountBuffer#record(gate_key, parts = nil, &exemplar)`:**
  - **when the key is known**, it bumps the counter, last seen and the bucket tally in place, with
    `Time.now`, and allocates no hash or array;
  - **when the key is new**, it calls the block inside `compute_if_absent`;
  - **when the map is full**, it counts into the overflow as today, without calling the block.

  `snapshot!` writes times with `in_time_zone.iso8601`, so its output is byte-for-byte what 0.17.0
  wrote.

## Decision: Build the exemplar lazily, from a per-call identity, not from a cache   (→ REQ-1, REQ-2, REQ-3, REQ-5)

**Context.** `gate_parts` (`gate.rb:247-289`) computes everything for every event. Its cost:
- the identity digest, 1.75 µs (reads high: a later probe gave 0.8 µs for all of `opaque_identity`
  on a 55-byte input);
- `scrub_deep`, 1.42 µs;
- normalisation, 1.21 µs;
- redaction, 0.69 µs;
- the app frame twice, 0.26 µs each.

Only the key is used unless the count buffer stores a new entry (`count_buffer.rb:166`). The gate's
own rule is no shared mutable caches on the hot path ("thread safety by construction",
`gate.rb:179`). The custom fingerprint lambda is the user's code and today runs once per event.

**Alternatives.**
1. A per-call identity (locals only) and a block that builds the exemplar from it, which the buffer
   calls only on insert.
2. Keep `gate_parts`, but memoize it per fingerprint in a bounded map.
3. Make the expensive pieces cheaper in place: skip `scrub_deep` for valid strings, and look the
   frame up once.

**Case for 1.** The redaction, the scrub and most allocations leave the calm path and the
known-fingerprint path entirely. The probe measured the key alone at 2.62 µs, against 5.45 µs for
`gate_parts`. Nothing is shared between threads, so the gate's concurrency argument is unchanged.
The exemplar is built by the same code from the same inputs as today, so REQ-2 holds by
construction. The user's lambda still runs once per event.

**Case against 1.** The gate's structure changes (three methods where there was one), and the
buffer's `record` takes a block, which is easy to misuse. The block runs inside
`Concurrent::Map#compute_if_absent`, which holds that map bucket's lock. The block does redaction
there, which is bounded by the 500-character message limit, and it's the same work `gate_parts`
did before the call, now under the bucket lock. Option 3 is smaller, but it saves about 1.5 µs and
leaves the calm path over budget.

**Decision.** We chose option 1.
**Falsifiability.** We would reconsider if `bin/benchmark`'s storm rows fail on the machine of
record after this change, or if a spec shows a buffered entry that differs from `gate_parts` for
the same input.
**Fired-if.** manual

## Decision: The buffer counts a known key in place, with `Time.now`   (→ REQ-4)

**Context.** `CountBuffer#record` (`count_buffer.rb:63-68`) takes 1.71 µs for a key it already
holds. On every event it:
- builds a `TimeWithZone` (`Time.current`);
- builds a one-entry bucket hash;
- calls `add`, which builds two arrays to take a min and a max.

Times leave the buffer through `snapshot!` as ISO 8601 strings, and the flush job parses them back
(`parse_time`).

**Alternatives.**
1. A fast path for a known key: `Time.now`, compare-and-assign for first and last seen, and the
   bucket tally bumped directly. `snapshot!` formats with `in_time_zone` so its output is unchanged.
2. Keep `Time.current`, and remove only the allocations.

**Case for 1.** A plain `Time` is several times cheaper than a `TimeWithZone`, and the instant is
identical. Formatting in `snapshot!` happens once per flush, not once per event, and keeps the wire
format exactly as before.

**Case against 1.** Entries now hold a mix of `Time` (live records) and `TimeWithZone` (restored
entries). They compare correctly, but a reader of `Entry` sees two classes. Option 2 avoids that,
at the price of the most expensive call on the path.

**Decision.** We chose option 1.
**Falsifiability.** We would revert to `Time.current` if a flush ever writes a first- or last-seen
time that differs from the instant the event was recorded at, as seen in the REQ-4 spec or an
issue.
**Fired-if.** manual
