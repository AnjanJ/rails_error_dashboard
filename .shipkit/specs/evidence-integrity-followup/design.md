# Design: Evidence integrity — follow-up

Decision records for `spec.md`. Each records the context, the real alternatives, the case for and
**against** the choice, and a falsifiability clause.

Two of these (§F1, §F8) revisit decisions from `.shipkit/specs/evidence-integrity/design.md`.
Where they overturn an earlier record, they say so and mark it superseded rather than quietly
replacing it.

---

## F1. The D8 reversal condition has been met — take one seam, not the whole refactor

**Context.** The previous sprint's §D8 deferred the canonical event-envelope refactor, with this
clause: *"I would reverse this if two or more of P1–P4's fixes turn out to need the envelope to be
correct rather than merely cleaner."*

Four findings share a shape — R1 (Analytics reconstructs volume independently of Overview), R3
(the producer discards timing the consumer needs), R7 (each consumer re-derives what "fresh"
means), R9 (each transport re-parses its input): **a contract with no single owner, so each
reader reconstructs it and they disagree.**

**But they do not all demand the same remedy, and this record no longer claims they do.** The
earlier framing — that four findings prove a canonical *capture envelope* became necessary — was
an overclaim. Analytics aggregation (R1), producer-side bucketing (R3) and snapshot provenance
(R7) are **separate responsibilities**; only R9 is about the capture envelope proper. What the
findings actually establish is narrower and sufficient: *shared contracts beat per-reader
reconstruction*, in three distinct places.

So §D8's literal condition is met, and the record is **superseded** — but the remedy chosen here
is **three bounded seams**, described as the chosen remedy rather than as proof that the full
refactor is now mandatory. The reviewer's own recommendation has the same shape: *"one normalized
capture envelope, one event-volume query model, one explicit snapshot-provenance policy"* — three
things, not one.

**Alternatives.**
1. Do the full envelope refactor now, and fix the nine findings as part of it.
2. Take exactly the seams the nine findings force — one normalization point (REQ-F20), one
   volume primitive (REQ-F6), one provenance policy (REQ-F17) — and leave the model separation
   (event / group / exemplar / aggregate) to `.shipkit/specs/event-envelope/`.
3. Fix the nine findings locally again, defer everything.

**Case for (2).** The findings name three specific seams, and each is independently testable and
independently shippable. R6 is a live secret leak and R9 is live data loss; neither should wait
weeks behind a model refactor. Critically, (2) is what makes the refactor *cheaper*: after this
sprint there is one volume primitive to move, not fifteen call sites, and one normalization point,
not two transports.

**Case against (2).** It is the same bet §D8 made, and §D8's bet is why we are here — "fix the
contract, defer the model" produced a half-migrated `EventVolume` and a page that disagrees with
itself. Taking three seams and stopping risks the same outcome one layer up. The honest mitigation
is REQ-F8's cross-page invariant and NFR-F8: a fix is not done until a test covers the dimension,
so a future half-migration fails a test rather than a review.

**Why not (1).** It blocks a plaintext secret leak (R6) and silent async data loss (R9) behind a
multi-week change, and it would do the refactor while `ErrorLog` still has no executable agreement
test between its readers. The invariants this sprint adds are exactly what makes that refactor
safe to attempt.

**Why not (3).** It is the choice that failed. Repeating it after the reviewer has named the
pattern would be indefensible.

**Decision.** Option 2 — three bounded seams (one normalization point, one volume model, one
provenance policy), taken as the chosen remedy for these nine findings, **not** as a commitment
that the full event-envelope refactor is now a prerequisite.
`.shipkit/specs/evidence-integrity/design.md` §D8 is marked **superseded by this record** on its
literal terms; whether the full refactor is warranted remains an open question for
`.shipkit/specs/event-envelope/`.
**I would reverse this if** the R1 cutover (REQ-F6) cannot be completed without changing
`ErrorLog`'s model boundaries — that would show the model separation is a prerequisite and not a
successor, and the envelope spec moves ahead of the remaining findings.

---

## F2. Redaction: filter the whole value under its name, once, whatever its container

**Context.** The previous fix wrapped Hash values under `var_name` before filtering and left the
Array branch calling `filter_array_recursive` directly, dropping the path
(`variable_serializer.rb:266`). Reproduced: with `filter_parameters = ["profile.private_note"]`,
`profile = [{private_note: "SECRET"}]` stores `[FILTERED]` in request params and the plaintext
secret in locals.

**Alternatives.**
1. Add the same wrap to the Array branch.
2. Filter the **complete** variable value under its name once — `filter.filter(var_name => value)[var_name]`
   — before any container-specific walk, and delete the per-shape branches.
3. Pre-walk the value and hand-roll path construction for every container type.

**Case for (2).** It removes the class of bug rather than its second instance. The defect is that
the code asks "what shape is this?" before asking "what is its path?"; `ParameterFilter` already
handles arbitrary nesting of Hash and Array, so the shape question should not be asked at all.
One call site means a third container shape cannot reintroduce the gap.

**Case against (2).** It changes the code path for values that are currently correct (plain
hashes), so the existing **31** filtering examples become the regression surface for a larger
rewrite than (1). It also allocates the one-key wrapper for scalars that would not have needed
it, a small cost on the capture path (NFR-2). And the wrap alone does not satisfy REQ-F4 — the
pipeline order has to change too, because `filter_serialized` currently receives values that
already carry display metadata (see T-F1.2).

**Why not (1).** It is the minimal fix, and it is exactly the mistake under review: patching the
shape that was reported. A `Set`, a nested `Array` of `Array`, or a custom `Enumerable` reaching
the same branch later would leak again, and nothing in the code would prevent it.

**Why not (3).** Hand-rolling path matching is what the previous sprint's §D3 rejected for good
reason. The precise mechanism, verified: a Proc filter is called with `(key, value)` or
`(key, value, original_params)` — **not** a constructed dotted path — so emulating
`ParameterFilter` means reimplementing both its traversal and its Proc contract. Unchanged, and
now stated accurately.

**Decision.** Option 2, with REQ-F5's shape matrix as the executable statement of the contract.
**I would reverse this if** profiling shows the unconditional wrap costs more than 0.1ms per
capture at the p99 variable count — then wrap only when the value is a container, keeping one
code path for all container types.

---

## F3. Analytics: route through `EventVolume`, and assert the two pages agree

**Context.** `analytics_stats.rb` has zero `EventVolume` references and twelve
`sum(:occurrence_count)` call sites; `base_query` still filters groups by first-seen `occurred_at`.
The wider inventory is **21 sites across 5 files** — `dashboard_stats.rb` is only partly cut over
(`top_errors`, `errors_by_severity_7d`), and `platform_comparison.rb`, `user_impact_summary.rb`
and `digest_builder.rb` were never in scope at all (T-F2.3).
Reproduced: Overview reports 1 event today, Analytics reports 0 for a 30-day window, while
Analytics' own user table shows the event. Previous-sprint task T3.6 claimed this cutover.

**Alternatives.**
1. Complete the cutover: route every volume figure in `analytics_stats.rb` through `EventVolume`,
   keep group metrics on `base_query`.
2. Have `AnalyticsStats` delegate wholesale to `DashboardStats` for volume.
3. Widen `base_query`'s group filter to include recently-seen groups.

**Case for (1).** It is the fix the previous sprint specified and did not finish, and the
primitive already exists and is tested. It keeps the two pages' differing filter/grouping needs
(Analytics filters by type, platform, environment; Overview does not) without forcing one into
the other's shape.

**Case against (1).** Twenty-one call sites across five files is the largest mechanical surface
in this sprint, and each is a chance to miss one — which is precisely how we got here. The mitigation is REQ-F8: a
cross-page invariant test means a missed site fails a test rather than a review. That test matters
more than the cutover itself.

**Why not (2).** The two pages genuinely differ in filtering and breakdown dimensions; collapsing
them would either lose Analytics' filters or push them into `DashboardStats`, which would then
serve two masters. It also hides the disagreement rather than asserting its absence.

**Why not (3).** This is the interim the previous sprint's adversarial pass already rejected
(§D4): it still sums a group's whole lifetime into the window, and is wrong in the opposite
direction. Rejecting it a second time, for the same reason, on the record.

**Decision.** Option 1, sequenced so REQ-F8's cross-page invariant test is written **first** and
observed failing, then the cutover makes it pass.
**I would reverse this if** the invariant test proves impossible to state without the two pages
sharing a filter model — that would mean the right fix is a shared query object, i.e. option 2
done deliberately rather than by delegation.

---

## F4. Time zone: one reporting zone, used for both SQL keys and Ruby lookups

**Context.** `EventVolume#day_expression` emits `DATE(column)` over UTC-stored timestamps while
callers look up `Date.current` in `Time.zone`. Reproduced at 00:15 IST: a fresh capture stored at
`2026-09-19T18:45Z` reports `today: 0` and lands on the 19th.

**Alternatives.**
1. Convert in SQL to the application zone before taking `DATE(...)`, per adapter.
2. Keep SQL in UTC and convert the *lookup* keys to UTC, presenting UTC days.
3. Fetch per-day counts and re-bucket in Ruby.

**Case for (1).** "Today" must mean the operator's today; that is the whole complaint. Converting
in SQL keeps grouping in the database (NFR-6) and makes the bucket key and the lookup key the same
by construction rather than by two call sites agreeing.

**Case against (1).** It is per-adapter SQL (`AT TIME ZONE` on PostgreSQL, `CONVERT_TZ` on MySQL —
which needs the tz tables loaded, a documented host requirement — and `datetime(..., 'localtime')`
is *not* equivalent on SQLite and must be handled by offset). That is three dialects plus a DST
policy, and it can be subtly wrong in a way a UTC-only test suite never notices. REQ-F11's
non-whole-hour and DST cases exist because of this.

**Why not (2).** It is defensible and cheap, but it means a dashboard that tells an operator in
Kolkata that their day starts at 05:30. The gem already renders times in `Time.zone`; a UTC-only
bucketing would make the chart disagree with the timestamps printed beside it.

**Why not (3).** Loading rows to bucket them in Ruby is the unbounded-memory shape this codebase
explicitly avoids (NFR-6, and three worked examples in `host-app-safety`).

**The bucket-boundary decision, made here rather than deferred.** "Document the policy" was an
evasion: an hourly **UTC** bucket cannot say how many of its events fell either side of a local
midnight at a non-whole-hour offset (Kolkata's +05:30 splits every UTC hour bucket). Deferring
that to implementation would leave the central accuracy question open. Two honest options:

- **(a) Boundary-compatible buckets** — bucket at a granularity that divides every supported
  offset, i.e. 30 minutes (or 15, to cover Nepal's +05:45). Day boundaries then always fall on a
  bucket edge and daily totals are exact for shed events.
- **(b) Keep hourly UTC buckets and report split days as approximate** — daily figures that
  include a split bucket are labelled incomplete/approximate rather than rendered as exact.

**Decision: (a), 15-minute buckets** for shed-event rollups, so every supported offset —
including +05:30 and +05:45 — lands on a bucket edge and daily totals stay exact. Occurrence rows
carry true timestamps and are unaffected. The cost is up to 4× the bucket rows of an hourly
scheme, bounded by the same one-row-per-group-per-interval shape and by §F8's cleanup.
**Acceptance is concrete:** a shed event at 23:59 local and one at 00:01 local, at offsets
+05:30, +05:45, −03:00 and UTC, must report 1/1 across the boundary — not 2/0.
If (a) proves too costly, (b) is the fallback and the UI must say "approximate", never show a
split-day figure as exact.

**SQLite and DST.** "SQLite by offset" must use the **offset in force at each row's timestamp**,
not one current offset applied across the whole window — a window spanning a DST transition would
otherwise misplace every row on one side of it. SQLite has no tz database, so either compute
per-row offsets from a Ruby-side zone table injected into the query, or restrict SQLite to
whole-window UTC with the incompleteness label from (b). This must be decided during T-F2.7 with
a DST-spanning test as its acceptance, not discovered later.

**Decision.** Option 1, zone resolved once (`Time.zone`), 15-minute boundary-compatible buckets
per the above, and the SQLite/DST mechanism settled in T-F2.7 with an executable DST case.
**I would reverse this if** MySQL hosts without loaded tz tables cannot be supported cleanly —
then the zone conversion becomes opt-in config with a documented UTC default, rather than silently
wrong on one adapter.

---

## F5. Storm timing: bucket at the producer, because the consumer cannot recover it

**Context.** `CountBuffer` stores one `count` plus `first_seen_at`/`last_seen_at` per fingerprint.
`FlushStormCounts` assigns the whole total to the hour of `last_seen_at`. Reproduced: 23:59:59 and
00:00:01 became two today, none yesterday.

**Alternatives.**
1. Key buffer tallies by `(fingerprint, bucket)` and reconcile each bucket separately. Per §F4 the
   bucket granularity is **15 minutes**, not an hour, so local-midnight boundaries at +05:30 and
   +05:45 fall on a bucket edge.
2. Split the total across `first_seen_at..last_seen_at` proportionally at flush time.
3. Accept it and label the storm temporal distribution approximate.

**Case for (1).** The reviewer's framing is exactly right: *"per-hour database buckets cannot
recover timing already discarded by the producer."* No amount of consumer cleverness fixes a total
that was already collapsed. Bucketing at tally time is the only option that produces the truth,
and the bucket key is one `Time#beginning_of_hour` on a path that already computes timestamps.

**Case against (1).** It multiplies buffer entries by the number of distinct hours a fingerprint
spans, which directly stresses the memory cap that exists because this path runs during overload.
A long-running storm crossing many hours grows a fingerprint's footprint. REQ-F14 keeps the cap
and overflow accounting binding, which means bucketing must degrade into the overflow counter
rather than around it.

**Why not (2).** It manufactures a distribution that was never observed — inventing evidence in a
feature whose entire purpose is trustworthy evidence. Strictly worse than admitting ignorance.

**Why not (3).** It is honest, and it is the fallback if (1) proves too costly. But the gem just
shipped a table whose stated purpose is giving shed events a timestamp; labelling that
approximate immediately after adding it would mean the table earns very little.

**Decision.** Option 1 at the §F4 granularity (15 minutes), with (3) as the documented fallback
if the memory cost is unacceptable under the cap. Note the granularity multiplies worst-case
buffer entries per fingerprint by the number of distinct intervals a storm spans, which is what
the reversal clause below measures.
**I would reverse this if** bucketing raises peak buffer memory for a realistic storm by more than
~25% at the configured cap — then the total stays collapsed, and the UI labels storm-derived
temporal distribution approximate per (3).

---

## F6. Transient bucket failure must not finalize the batch

**Context.** `EventCount.accumulate` rescues `StandardError` and returns `false`;
`FlushStormCounts` ignores the return value and commits the ledger. Reproduced: lifetime 10,
today 0, replay suppressed as `already_applied`. My own comment at `event_count.rb:72` reads
"Losing a bucket degrades a time window, it does not lose the count" — true of the lifetime
count, false of the temporal evidence 0.14.0 promises.

**Alternatives.**
1. Let transient bucket failures re-raise into the same rollback-and-retry path as transient count
   failures, reusing `LogError::RETRYABLE_STORE_ERRORS`; keep degrade-and-continue for permanent
   ones.
2. Track missing bucket work durably and report incomplete data.
3. Keep swallowing, and document that temporal data is best-effort.

**Case for (1).** It reuses the taxonomy and the exact mechanism P1 already established for the
count itself, so "transient" has one definition and one behaviour across both writes. Nothing is
committed, so nothing can double on retry — the same argument that made P1's abort safe.

**Case against (1).** It makes a rollup failure able to fail a whole batch, on the path that
exists because the system is already overloaded. A bucket write that is reliably failing would
turn into repeated batch retries, which is worse than a missing time window. The bound is
ActiveJob's retry limit, and REQ-F15 keeps permanent failures degrading rather than aborting.

**Why not (2).** It is the most complete answer and needs a durable queue of missing bucket work
plus a UI for incompleteness — a new subsystem to fix a case (1) already converts from silent loss
into retried work. It is the right escalation if (1)'s retry pressure proves real.

**Why not (3).** It is the status quo, and the status quo is a comment that rationalises the bug.

**Decision.** Option 1, and the misleading comment is corrected in the same commit (NFR-F10).
**I would reverse this if** transient bucket aborts cause a batch to exhaust its retries in
practice — then (2), with explicit incomplete-window reporting.

---

## F7. Bounded execution: serialize members, do not race arbitrary `#inspect`

**Context.** `serialize_object` calls `value.inspect`, *then* measures elapsed and swaps in a
summary if over budget. Reproduced: a Struct containing an object with a slow `#inspect` took
~35ms against a 5ms budget. The reviewer's phrasing is exact: *"a post-execution elapsed-time
check is an output-selection threshold, not an execution budget."*

**Alternatives.**
1. Serialize allowlisted structural types **member-wise** through the bounded serializer, so the
   parent's `#inspect` never calls arbitrary child implementations.
2. Run `#inspect` under a `Timeout`/watchdog thread.
3. Remove Struct/ActiveModel from the default allowlist.

**Case for (1).** It removes the unbounded call rather than trying to interrupt it. Struct and
ActiveModel were allowlisted because they print their own attributes cheaply — that premise is
true of the *container* and false of whatever it holds, and walking members restores it. Each
member then gets the same safe-summary default an unknown object already gets, so the rule is
uniform and needs no timing at all for this path.

**Case against (1).** It changes stored output for allowlisted types: a Struct renders as
structured members rather than its native `inspect` string, which is a second behaviour change on
top of 0.14.0's serializer default, and `variable_serializer_spec.rb:385` asserts real Struct
`inspect` output containing `"Alice"`. That spec must change deliberately, with the changelog
calling it out.

**ActiveModel is excluded — the reversal clause below was already met when this record was
written.** Reading `ActiveModel::Attributes#attributes` **runs a custom type's `cast`**: verified
directly, a type whose `cast` sleeps 20ms took 24.3ms to read. So member-wise serialization of
ActiveModel invokes arbitrary application code by a different door, without any `attributes`
override being involved. ActiveModel therefore gets a **safe summary** by default, not member-wise
traversal, unless a bounded side-effect-free extraction mechanism is identified (reading the
`@attributes` hash's *raw* values before cast might qualify; that must be proven, not assumed).

**Struct traversal needs explicit limits** too: member count, nesting depth, and per-member
budget, or a Struct of Structs reintroduces unbounded work through recursion rather than through
`inspect`.

**And the honest limit of REQ-F18:** any remaining opt-in for a type with a custom `#inspect`
cannot carry an unconditional bounded-execution guarantee, because the only way to interrupt
arbitrary Ruby mid-call is the `Timeout` mechanism rejected below. The guarantee is therefore:
*the default path never calls arbitrary `#inspect`*, and *opting a type in is documented as
accepting unbounded execution for that type*. REQ-F18 must be worded to that effect rather than
promising a bound it cannot deliver.

**Why not (2).** `Timeout.timeout` on the capture path is a thread plus an exception injected into
arbitrary application code mid-call — a direct violation of Safety Rule 1 and NFR-F9, and a
documented way to corrupt application state. Not acceptable on the request path.

**Why not (3).** It restores safety by removing a genuinely useful default: Struct and ActiveModel
attributes are what a developer most wants to read. It also leaves the mechanism wrong for anyone
who opts a type back in.

**Decision.** Option 1 **for Struct only**, with explicit member-count/depth limits; ActiveModel
takes a safe summary per the verified `cast` side effect above. The budget check stays as a
backstop for any remaining direct `#inspect` call, relabelled honestly as an output-selection
threshold rather than an execution budget.
**I would reverse this if** a bounded, side-effect-free ActiveModel extraction is demonstrated
(raw `@attributes` values read without cast, proven by a spec with a casting type) — then
ActiveModel rejoins member-wise traversal.

---

## F8. `EventCount` cleanup, and the fallback term that makes pruning lossy

**Context.** `EventCount` has `belongs_to :error_log, optional: true`, no foreign key, no
`dependent:`, and `RetentionCleanupJob` never references it. Both probes leave
`orphan_buckets: 1`. The migration comment claims retention prunes the table. Separately,
`EventVolume` has a third term that counts a group's lifetime `occurrence_count` against its own
`occurred_at` when the group has neither occurrence rows nor buckets — which means pruning a
bucket does not merely remove evidence, it **moves those events onto the group's first-seen day**.

This is a consequence of the previous sprint's §D4 that was not foreseen there; §D4's decision
stands, but this record extends it.

**Alternatives.**
1. `has_many :event_counts, dependent: :delete_all` on **`ErrorLog`** (not `dependent:` on
   `EventCount`'s `belongs_to` — Rails rejects that option there, verified) plus an explicit
   batched `EventCount` delete in
   `RetentionCleanupJob`, and prune buckets only for groups being deleted.
2. The above, plus time-based pruning of old buckets belonging to still-active groups.
3. A database-level `ON DELETE CASCADE` foreign key.

**Case for (1).** It fixes both reproduced cases with the pattern the job already uses for
occurrences, comments and cascade patterns, and it avoids the redistribution trap entirely: if a
bucket only ever disappears when its group does, the fallback term can never resurrect its events.

**Case against (1).** Buckets for a long-lived, never-expiring group accumulate at up to one row
per hour indefinitely. For a chronic error that is ~8,760 rows a year — small, but genuinely
unbounded, which is the objection this sprint raised against the table in the first place.

**Why not (2).** It is the real retention story, but it needs the fallback term neutralised first
(a pruned-before marker per group, or dropping the term), or pruning silently redistributes old
events. That is a bigger change than the finding requires, and doing it carelessly turns a
cleanup into a correctness bug. REQ-F25 requires the policy be *decided and documented* now; the
implementation is deliberately staged behind that decision.

**Why not (3).** Cascades across a gem's tables inside a host app's schema are a support burden.
(The earlier cross-database objection is **withdrawn**: `EventCount` and `ErrorLog` both inherit
`ErrorLogsRecord`, so they always share a connection and a FK between them is possible. The
support-burden argument stands on its own.) The codebase's own
convention is batched application-level deletes, for table-lock reasons the job documents.

**Decision.** Option 1 now; REQ-F25 documents the still-active-group policy and its interaction
with the fallback term, with (2) specced as follow-up. The false migration comment is corrected in
the same commit (NFR-F10, REQ-F26).
**I would reverse this if** a real deployment shows bucket rows for active groups exceeding the
order of the occurrence table — then (2) moves into this sprint and the fallback term is
neutralised as part of it.

---

## F9. PR grouping: four PRs by contract, security and data loss first

**Context.** Nine findings. Two are shipping-blockers (R6 secret leak, R9 data loss), one is an
unbounded table with a false comment (R5), and the rest are correctness work of varying size.

**Decision.** Four PRs:

| PR | Contract | Findings | Risk |
|---|---|---|---|
| **P-F1** | One redaction policy, every container shape | R6 | low, security-relevant — ship first |
| **P-F2** | One event-volume model + cleanup path | R1, R2, R5 | **high** — 21 call sites / 5 files, per-adapter tz SQL, 15-min buckets |
| **P-F3** | Storm timing + one provenance policy | R3, R4, R7 | medium |
| **P-F4** | Bounded execution + one normalization seam | R8, R9 | medium, R9 is data loss |

P-F1 and P-F4 are independent of the rest and of each other. P-F2 is the large one and is
sequenced so REQ-F8's invariant test lands before the cutover. P-F3 touches
`flush_storm_counts.rb` and `find_or_increment_error.rb` and should follow P-F2 to avoid
conflicting with the `EventVolume` work.

**Case against four.** R9 (data loss) rides in the last PR behind R8. If P-F4 slips, a silent
async drop stays live. Mitigated by R9 being a two-line normalization fix that can be split out
and shipped alone if P-F4 stalls — noted here so the option is pre-authorised rather than
improvised.

**I would reverse this if** P-F2 exceeds ~20 files or the tz SQL proves adapter-hostile — then the
time-zone work (R2), including the 15-minute bucket change, splits into its own PR behind the
cutover.

---

## F10. Release: hold 0.14.0

**Context.** `EventVolume`, `EventCount` and the migration are **new in 0.14.0**. R2, R3, R4 and
R5 are therefore defects this unreleased version would *introduce*, not pre-existing ones. R9 is a
new async data-loss path from the same PR. R6 is a plaintext secret at rest. Merging release PR
#237 is the irreversible publish.

**Alternatives.**
1. Hold #237; ship P-F1..P-F4; release once.
2. Publish 0.14.0 now, fix forward in 0.14.1.
3. Revert the `EventVolume`/`EventCount` work from `main` and release the rest.

**Case for (1).** A user upgrading to 0.14.0 gets a migration, a table with no cleanup path, a
dashboard whose two pages disagree, wrong days outside UTC, and a new way to silently drop async
captures — all attributable to this release. Holding costs little: 0.13.0 is already published,
and while it is **not** free of findings, the ones it carries are *pre-existing*, not newly
introduced.

**Which findings 0.13.0 actually carries** (the earlier "unaffected by every new finding" was too
broad):

| Finding | In 0.13.0? |
|---|---|
| R6 array redaction leak | **yes** — pre-existing; the Hash-only wrap shipped in 0.14.0's P2, but arrays never had the path either |
| R7 provenance over context payloads | **yes** — pre-existing |
| R8 Struct/nested `inspect` | **partly** — 0.13.0 called `inspect` on everything; 0.14.0 narrowed it but left the Struct door |
| R1 Analytics lifetime volume | **yes as a defect**, though `EventVolume` (the half-done remedy) is 0.14.0-only |
| R2, R3, R4, R5, R9 | **no** — introduced by 0.14.0 |

**Case against (1).** It also withholds seven genuinely good fixes (storm conservation, queue and
tracing redaction, per-user attribution, async time/release, manual fields, job breadcrumbs,
mobile layout), two of which are security-relevant, from users running 0.13.0 today. That is a
real cost, not a rhetorical one.

**Why not (2).** Publishing a version whose headline feature is "trustworthy evidence" while
holding nine confirmed evidence defects — four of them introduced by that feature — is the exact
credibility failure this whole effort exists to avoid.

**Why not (3).** Reverting a merged migration is messier than fixing forward, and it would discard
the correct core of the work. The findings are completions, not a failed design.

**The fallback must name a real tree.** The earlier version of this record said "ship P-F1 and R9
alone as 0.14.0", which does not work: release PR #237 builds from `main`, and `EventVolume`,
`EventCount` and the migration are **already merged there** (verified). Merging #237 with P-F1 and
R9 added would still publish R2/R3/R4/R5 along with them. A genuinely smaller release requires one
of:

- **(i) A release branch from the published baseline.** Branch from `9664789` (v0.13.0), cherry-pick
  only P-F1 (R6) and the R9 normalization, release as **0.13.1**, and leave `main` unreleased until
  the full plan lands. Cleanest, and it is a patch release of pre-existing fixes — which matches
  what R6 and R9 are relative to 0.13.0.
- **(ii) Explicit removal from `main`.** Revert `EventVolume`, `EventCount` and the migration
  (and the `dashboard_stats.rb` call sites that now depend on them), then release. Larger, riskier,
  and it discards work that is correct in its core.

**(i) is the chosen fallback.** Its acceptance is concrete: the branch must build, pass the full
suite, the browser suite and chaos on SQLite and PostgreSQL, contain **no** `event_counts`
migration, and its probe run must show R6 and R9 passing with R2/R3/R4/R5 **not applicable**
(the feature is absent). That tree gets verified before anything is published — it is not a
hypothetical.

**Decision.** Option 1: **hold release PR #237**, do not merge.
**I would reverse this if** a user is actively blocked on a fix — then fallback (i) ships as
0.13.1 from the released baseline, verified as above, with the remaining findings documented as
known issues.

---

# Round 3 — four contract failures at `e92c04a`

An independent review confirmed 5,111 tests and all ten original probes passing, then found four
further contract failures with four new checks. **Two were introduced by this sprint's own fixes**
(F11, F13), which is the pattern worth naming: a fix that establishes a property in one place and
does not carry it to the place that consumes it.

## F11 — one bucket definition, shared between producer and storage

**Context.** `CountBuffer::BUCKET_SECONDS = 900` was chosen in this sprint precisely because every
UTC offset in use divides into 15 minutes (+05:30, +05:45 included), so a local midnight falls on a
bucket **edge**. `EventCount.bucket_for` was never updated and still called `utc.beginning_of_hour`,
which destroys exactly that property. Two storm events straddling midnight in Kolkata were stored
together and both landed on yesterday — the same off-by-a-day the table was introduced to fix.

**Alternatives.** (1) Derive `EventCount::BUCKET_SECONDS` from the producer's constant.
(2) Restate `900` in the model. (3) Store at minute resolution. (4) Convert at read time.

**Case for (1).** The bug is two definitions of one concept drifting apart; deriving one from the
other makes drift impossible rather than merely unlikely. (2) would fix today's symptom and leave
tomorrow's drift available. (3) grows rows without bound through a long storm — the row count is the
reason a bucket width exists. (4) spreads the concern across every reader, and one reader forgetting
is precisely how this arose.

**Case against (1).** It couples a model constant to a service constant across layers, which is a
dependency direction the CQRS split otherwise avoids. Accepted: the coupling is the point, and it is
one line with a spec asserting it.

**Decision.** (1), plus a parity spec that asserts agreement in both named offsets and end to end.
**I would reverse this if** the two ever need genuinely different widths — at which point the
conversion must become explicit and tested at the boundary, not implicit in each reader.

## F12 — Overview's breakdowns routed through EventVolume

**Context.** The previous sprint inventoried `top_errors` and `errors_by_severity_7d` and migrated
neither. Reopening an August group in September gave an empty top-errors list and zero across every
severity while the headline total counted the event.

**Alternatives.** (1) Fold severity from the same per-type breakdown `top_errors` uses. (2) Four
independently scoped `EventVolume` sums, one per severity band.

**Case for (1).** One query instead of five, and — the real reason — the two figures then agree
**by construction**. (2) leaves two independent paths that can drift, which is the failure mode
this whole document is about.

**Case against (1).** Severity banding moves from SQL into Ruby, so the classifier arrays are walked
per error type. Bounded by the number of distinct types in the window, not by events; acceptable.

**Decision.** (1). **I would reverse this if** the per-type breakdown ever needs to be capped or
sampled, since severity totals must stay exact and would then need their own query.

## F13 — permanent unavailability degrades; transient failure retries

**Context.** `accumulate` returned `false` for a rescued transient failure *and* for permanent
unavailability. The caller escalated every `false` into an exception that aborted the transaction,
so a host that had never migrated the rollup table lost its lifetime counts entirely.

**Alternatives.** (1) Three-state return (`:written` / `:unavailable` / raise). (2) Rescue
`EventCountWriteFailed` in the caller. (3) Check `table_exists?` before the flush.

**Case for (1).** The caller genuinely needs to distinguish three outcomes; a boolean cannot carry
three states, so any fix layered on top of it is a workaround. (2) is too late — the abort has
already rolled the transaction back. (3) races, and misses every permanent cause that is not a
missing table.

**Case against (1).** A symbol return is less idiomatic than a boolean and every caller must be
updated. There is one caller, and the spec pins the new contract.

**Precedent.** This is the host-app-safety rule that data loss is preferable to application damage,
applied one level down: losing a *time bucket* is acceptable, losing the *authoritative count* is
not. The incompleteness is surfaced (`buckets_incomplete`), not swallowed — sentry-ruby#1246.

**Decision.** (1). **I would reverse this if** a second failure mode appears that needs distinct
handling, at which point the return type should become a small result object rather than more
symbols.

## F14 — hourly aggregation bounded by the window

**Context.** `by_hour_of_day` grouped by the raw timestamp, so 1,000 events inside one second
returned 1,000 intermediate rows to Ruby to produce 24 bins.

**Alternatives.** (1) Bin in SQL per adapter. (2) Pluck and bin in Ruby. (3) A materialized rollup.

**Case for (1).** It matches the three memory-bounding patterns already established in
host-app-safety ("aggregate in the database, not in Ruby"), and reuses `day_expression`'s existing
per-adapter shape — including the **named** MySQL zone, since a numeric offset misplaces rows across
a DST boundary. (2) is the unbounded shape being removed. (3) is far more machinery than a
`GROUP BY` needs.

**Case against (1).** A third adapter-specific SQL expression to maintain, and SQLite still converts
in Ruby — though now from at most one row per window-hour rather than one per event.

**Decision.** (1). **I would reverse this if** an adapter appears whose hour extraction cannot be
expressed in SQL, which would force the Ruby path to become the general one.

## F15 — a green test that tested nothing

The agreement spec's user-table example read `:user_impact` / `:affected_users`, keys
`AnalyticsStats` has never returned, so `next if users.blank?` fired every run and the example
exited before asserting anything.

**This is the most instructive item in the round.** A test that is green and asserts nothing is
worse than a missing test, because it is counted as coverage and suppresses the instinct to write
the real one. The fix is `fetch`, which **raises** on a wrong key, over `[]`, which returns nil and
lets the example skip: prefer the accessor that fails loudly when a test's own premise is wrong.

**I would reverse this if** an example legitimately needs to skip on absent data — in which case the
skip must be an explicit `skip` with a reason, never a silent `next`.

---

# Round 4 — three implementation findings at `3f05b28`

## F16 — one unambiguous time key, both aggregation paths

**Context.** SQLite has no tz database, so both the hourly and daily groupings bucket in Ruby. The
hourly key was `'YYYY-MM-DD HH:00:00'` and the daily key was the raw timestamp. Three defects fell
out of that: `Time.zone.parse` read the hourly string as LOCAL (10:15 UTC reported hour 10 in New
York, not 6); truncating to the UTC hour destroyed the sub-hour boundary +05:30 and +05:45 need
(Kolkata 00:15 and 00:45 collapsed into one bin instead of hours 5 and 6); and the daily path
returned one row per distinct instant (200 rows for 200 events in a day).

**Alternatives.** (1) Emit a UTC **epoch-second** bin and read it as an integer. (2) Keep the
datetime string and parse it with an explicit UTC zone. (3) Bucket entirely in Ruby from plucked
timestamps.

**Case for (1).** (2) fixes today's bug and leaves the next reader one `Time.zone.parse` away from
reintroducing it — the ambiguity survives in the data format. An epoch second has no local-vs-UTC
reading at all, so the defect class becomes *unrepresentable* rather than corrected. (3) is the
unbounded shape being removed.

**Case against (1).** The grouping key is no longer human-readable in a query log, and two constants
(`HOUR_BIN_SECONDS`, `DAY_BIN_SECONDS`) now restate 900 rather than referencing
`EventCount::BUCKET_SECONDS`. The latter is forced: that model is autoloaded and the constant is
evaluated at class-definition time — referencing it broke the gem at boot. Guard specs assert all
three stay equal.

**Why 15 minutes.** It divides every UTC offset in use, so a local hour AND a local day boundary
always fall on a bin edge. An hour-wide bin is not safe in fractional zones — that is defect two.

**Decision.** (1), applied to BOTH paths, with `local_hour` dispatching on ADAPTER rather than value
shape: a SQLite epoch bin *is* a Numeric and would otherwise fall into the PostgreSQL branch and
silently return garbage.
**I would reverse this if** an adapter appears whose hour/day extraction cannot be expressed in SQL
and whose keys cannot be made unambiguous, forcing the Ruby path to become the general one.

## F17 — incompleteness is persisted state, not a return value

**Context.** `buckets_incomplete` was an instance variable copied into the flush result. No model,
query or view consumed it; a background job's return hash never reaches the dashboard; and an
idempotent replay returns `already_applied` with no flag at all. The dashboard therefore presented
incomplete timing as an ordinary quiet period.

**Alternatives.** (1) Persist on the storm EPISODE (`storm_events.buckets_incomplete`). (2) Persist
per affected ErrorLog group. (3) Recompute at read time by comparing counts to bucket coverage.

**Case for (1).** Incompleteness is a property of the EPISODE — one storm, one degradation event —
and `StormEvent` already accumulates exactly this kind of per-episode fact. It survives the job
boundary and the replay for free, because the state is not in the result hash the replay declines to
build. (2) multiplies rows and answers a narrower question than the dashboard asks. (3) cannot work:
once the timing evidence is discarded there is nothing left to compare against — the finding is about
*recording* uncertainty, not reconstructing timestamps.

**Case against (1).** It needs a migration and a new column on a host that may never have had a
storm. Mitigated by an additive boolean defaulting to false, guarded at both ends by a
column-existence check so an unmigrated host keeps flushing and rendering normally.

**Sticky, like `reached_open`.** Once an episode has lost bucket timing it has lost it; a later
successful flush does not make the earlier gap reappear.

**The window predicate was wrong on the first attempt,** and the reviewer's fixture is what caught
it. I filtered `started_at >= beginning_of_day`; a storm that began yesterday and is still shedding
today is the ORDINARY case, and it was missed. Now matched on the episode's overlap with today.
My own fixture flushed everything today and passed — a reminder that a fixture which is easier than
production tests the easy case.

**Decision.** (1), surfaced as `:event_timing_incomplete` and banner-rendered in all 11 locales,
mirroring the existing `affected_users_incomplete` contract rather than inventing a new mechanism.
**I would reverse this if** incompleteness ever needs to be attributed to a specific group or time
range rather than an episode, which would force per-group rows.

## F18 — the probe claim I got wrong

I stated the review's probes "were diagnostic `puts` scripts, not assertions", and repeated it in a
commit body, a PR description and a public issue comment. **It was false.** Three of the eight carry
real `expect` calls (8 in the precedence probe, 1 each in payload and persistence). I generalized
from the five that do not.

Two things followed from that overreach, both now corrected:

- `event_volume_invariants_spec.rb` was presented as replacing the probes. It does not — it covers
  the event-volume invariants only. It now carries an explicit probe → permanent-test mapping that
  names what is NOT carried over (ActiveJob-lifecycle, UI/layout).
- Its "Overview and Analytics agree" examples called only Overview, and its three-term test asserted
  `count == a + b + c` against an implementation that DEFINES `count` as `a + b + c`, with two terms
  zero. The first now calls both pages; the second builds each term by a different mechanism and
  asserts each is nonzero before checking an independently computed total.

**The lesson worth keeping:** a claim about someone else's artifact is cheap to verify (`grep -c
'expect('`) and expensive to retract once published. Verify before asserting, especially when the
claim flatters your own work — "their tests were weak, mine are strong" is exactly the claim that
deserves the most scrutiny.

---

# Round 5 — the completeness warning, done properly

## F19 — the warning belongs to the interval, not to an episode

**Context.** Round 4 put `buckets_incomplete` on the storm EPISODE, written by `upsert_storm_event`.
Three failures followed, and they are one failure wearing three hats: **the warning was attached to
an optional, post-commit object.**

- The episode is optional. The gate sheds with its breaker closed and passes `episode: nil`, so
  `return unless @episode.is_a?(Hash)` dropped the marker entirely — reproduced as
  `buckets_incomplete: true`, zero episodes, dashboard reporting completeness.
- `upsert_storm_event` runs AFTER the counts transaction commits and rescues its own failures. A
  transient save lost the marker while the batch ledger had already recorded the batch as applied,
  so the replay was suppressed and the gap was never recorded at all.
- The predicate asked only about today while the same page shows 7-day and 30-day figures that still
  contained the affected events.

**Alternatives.** (1) A dedicated `event_timing_gaps` table keyed by the interval. (2) A column on
`error_logs`. (3) Keep the episode and add a nil-guard fallback.

**Case for (1).** The thing that is unreliable is a TIME INTERVAL, so that is what should be
recorded. It requires no optional collaborator, and being its own row it can be written inside the
counts transaction — which is what makes failures recoverable rather than silently swallowed.

**Case against (1).** A new table and migration for what is, on a healthy install, always empty.
Accepted: it is written only while the rollup is genuinely unusable, which is a misconfiguration
rather than a steady state, and the read side degrades to `false` when the table is absent.

**Why not (2).** `error_logs` already has 88 columns, and a gap describes a window, not a group —
the same group can have some events timed and others not.

**Why not (3).** A nil-guard keeps the optional dependency that caused the first failure. Fixing the
symptom while preserving the structure is how round 4 produced round 5.

**Atomicity is the point.** The gap is created inside the same transaction as the counts. If it
cannot be written the whole batch rolls back and stays replayable. Committing counts whose
unreliability we failed to record is strictly worse than retrying them.

**Decision.** (1), read against `WIDEST_DISPLAYED_WINDOW` so the warning covers every figure on the
page rather than the narrowest one.
**I would reverse this if** incompleteness ever needs attributing to a specific group rather than an
interval, which would require a join table instead.

## F20 — retention for a table with no parent

The new table has no `error_log_id`, so nothing in `RetentionCleanupJob` would ever have pruned it
and it would have grown for the life of the installation. Pruned on `covered_until`, and
deliberately placed ABOVE the early return that fires when no error logs are expired — gaps expire
independently of errors, exactly like the rack-attack rows whose comment already warns about that
trap. **A new table is not finished until something deletes from it.**

## F21 — a spec that is green only by daylight

The volume invariants placed fixtures at 2 and 3 hours ago and queried "since midnight". Run at
00:30 both fixtures fell outside the window and the total came out 3 instead of 15.

**This is the worst shape a failing test can take:** green whenever a human looks at it, red only
for whoever runs CI after midnight — and then dismissed as a flake, because it passes on re-run in
the morning. It is the same trap as the notification-burst "flake" earlier in this project, which
turned out to be a real order-dependent defect.

**Decision.** Pin the clock, do not widen the window. Widening makes the symptom go away and leaves
the dependency in place. Audited the sibling specs added this sprint and found two more with the
same latent pattern (minute-scale offsets against day-boundary queries); both pinned.
**I would reverse this if** a spec genuinely needs to assert real-clock behaviour, which would make
the dependency the subject of the test rather than an accident of it.

**The meta-lesson, now three rounds old:** every round of this review has found that I fixed a
symptom while preserving the structure that produced it — hashes but not arrays, Overview but not
Analytics, the episode marker but not its optionality. The question to ask before calling a fix
done is not "does the reported case pass" but "what shape of thing produced this, and is that shape
gone".

---

# Round 6 — the two clocks that govern completeness evidence

## F22 — evidence outlives the shorter clock, and stops at the longer one

**Context.** Round 5 added gap pruning on the configured retention cutoff. The Overview reads gaps
against a 30-day window. Those are two different clocks, and whenever retention is the shorter of
them the evidence disappeared while the figures it qualified were still displayed: at
`retention_days = 7`, `month=10` before and after cleanup, warning `true` → `false`, group still
active.

**Why the original spec missed it.** It used the 90-day default, where the retention cutoff is
already the later of the two clocks. **A spec that exercises only the default value cannot find a
bug that lives in the configurable range.** That is the durable lesson here, not the arithmetic.

**Alternatives.** (1) Delete only once BOTH clocks have passed: `min(retention_cutoff,
WIDEST_DISPLAYED_WINDOW.ago)`. (2) Prune gaps strictly by the reporting window, ignoring retention.
(3) Delete a gap when the events it covers are gone.

**Case for (1).** It states the actual invariant — completeness evidence must outlive the horizon it
qualifies — and it is a no-op on the default, so no existing install retains more than before.
(2) ignores an explicit user setting for the longer-retention case. (3) is the correct idea and
impossible to implement cheaply: a gap has no group key by design (F19), and re-deriving "are any
covered events still present" per gap is a scan on the dashboard path.

**Case against (1).** Rows now survive their nominal retention, which a user reading
`retention_days` might not expect. Bounded: gaps are written only while the rollup is genuinely
unusable, and the extra horizon is capped at the reporting window.

**Decision.** (1).
**I would reverse this if** the Overview ever displays a window wider than the gap table can
comfortably hold, at which point pruning needs its own configurable horizon rather than borrowing
one.

## F23 — the warning must not outlive its own subject

Retaining a gap past its retention creates the case the review named in advance: the gap can outlive
every event it covered, because expiring the GROUP is what removes those events. Reproduced as a
banner qualifying a window showing **zero** events.

**Alternatives.** (1) Guard the read — no events in the window, no warning. (2) Shorten the
retention again. (3) Delete the gap when its events vanish.

(2) reintroduces F22 exactly. (3) is F22's option (3), rejected for the same cost reason.

**Decision.** (1), with the widest-window count memoised — the stats hash and the predicate need the
same number, and this runs on the capture path via the stats broadcast, so a second identical
aggregate is pure waste. **Noise in a warning is not harmless: it trains people to ignore the
banner**, which costs more than the missing warning it was added to prevent.
**I would reverse this if** the warning ever needs to describe a window the page does not display,
where "no events shown" would stop implying "nothing to qualify".

**Pattern note, six rounds in.** Rounds 4, 5 and 6 each found a defect in the previous round's fix.
The common shape is not carelessness but **scope**: each fix was correct for the case reported and
wrong for a neighbouring case I had not enumerated — a nil episode, a post-commit window, a
non-default setting. The check that would have caught all three is the same one: before calling a
fix done, list the inputs it depends on (optional collaborators, transaction boundaries,
configurable values) and ask what each one does at its extremes.
