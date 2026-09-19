# Spec: Evidence integrity sprint

> Spec written at commit `9664789` on main (2026-09-19), gem v0.13.0. Not yet accepted —
> the Q1 gate is the scope/sequencing decision in `design.md` §D9 and the release shape in §D10.
>
> Source: external review at `review-evidence/2026-09-19/REVIEW.md`, assessed against
> commit `0fd824c`. Re-verified independently at HEAD `9664789` (v0.13.0) — 14 findings,
> 14 confirmed real (one "partly-real"), 0 refuted, by 13 verifier + 13 adversarial-challenger
> agents plus hand reproduction. Evidence: `.shipkit/specs/evidence-integrity/verification.md`.

## Purpose

RED's product promise is that the evidence it shows about a failure is **trustworthy**: the
count is the count, the day is the day, the user is the user, the release is the release, and
what was filtered stays filtered. The review found that four separate capture paths (sync,
async, storm, manual) implement slightly different versions of that contract, and that the
dashboard's time-window numbers answer a different question from the one they are labelled with.

This sprint fixes the contract violations. It explicitly **defers** the architectural refactor
(a canonical immutable event envelope; separating event / group / exemplar / aggregate) to a
follow-up — see `design.md` §D8 for why, and what this sprint does to make it cheaper later.

### A note on what was NOT wrong

The review reported that `version.rb` declares 0.12.1 while the changelog prepares 0.13.0.
That is an artifact of reviewing a stale checkout: commit `9664789` (upstream, one commit
later) is the release-please bump to 0.13.0. The diff between the reviewed commit and HEAD is
**only** the version bump and changelog — no implementation file changed, so every code finding
below still applies at HEAD. This is not a defect and has no task.

## Scope

**In scope.** The 14 confirmed findings, grouped into 5 shippable PRs (P1–P5).

**Out of scope, deliberately.**
- The canonical event-envelope refactor and model separation (`design.md` §D8).
- The demo app's `GET /admin/seed` destructive endpoint. Real and worth fixing — it performs
  destructive seeding behind only the publicly-documented demo credentials — but it lives in
  `rails_error_dashboard_demo_app`, a separate repository. Tracked separately; **not** a gem
  defect and not a gem auth bypass.
- Re-running the full advertised Ruby/Rails/MySQL compatibility matrix (the release process
  already owns that via `bin/pre-release-test all`).

## User stories

- As an on-call engineer, I want "errors today" to mean events that happened today, so that an
  error recurring at 00:01 is not invisible until tomorrow.
- As an operator during a storm, I want every shed event to eventually be counted exactly once,
  so that the count I use to judge severity is neither short nor doubled.
- As a developer investigating a regression, I want a queued error to carry the release and time
  it was *captured* under, so a slow queue across a deploy does not blame the wrong version.
- As a security-conscious integrator, I want my `filter_parameters` to protect captured
  variables with the same path semantics Rails applies to request params.
- As a developer using the gem's documented manual-report API, I want the fields I pass to be
  retained, or to be told they are not supported.
- As an on-call engineer at 3am on a phone, I want the error detail page to be readable.

## Requirements (EARS)

### A. Storm count conservation (P1)

- **REQ-1.** When two or more storm batches reconcile concurrently against the same resolved
  error group, the system shall increase `occurrence_count` by exactly the total number of
  reconciled events. *(F1)*
- **REQ-2.** While reopening a resolved group from a storm flush, the system shall perform the
  count update as a locked read-then-write or an atomic SQL increment, and shall preserve the
  existing reopen state transition (`resolved: false`, `status: "new"`, `resolved_at: nil`).
- **REQ-3.** The reopen path shall continue to fire the `after_update_commit` broadcast
  callback, so live dashboard updates are not silently lost. *(This forbids a bare `update_all`
  for this branch — see `design.md` §D1.)*
- **REQ-4.** If a storm batch entry fails with a **transient** store error
  (`LogError::RETRYABLE_STORE_ERRORS`), then the system shall abort and roll back the entire
  batch, leave the batch ledger unclaimed, and allow the job to retry the whole batch. *(F2)*
- **REQ-5.** If a storm batch entry fails because the entry is **permanently** malformed
  (non-Hash, missing identity, unparseable), then the system shall skip that entry, count it in
  `failed:`, and mark the batch applied — the current behavior, which is correct for this class.
- **REQ-6.** The system shall report transient-abort and permanent-skip distinguishably in the
  command's return value, so the job can tell "retry me" from "this entry is garbage".

### B. Redaction boundary parity (P2)

- **REQ-7.** Where a captured variable's value is filtered, the system shall apply the filter
  with the variable's own name as the top-level key, so that dotted `filter_parameters`
  patterns (e.g. `profile.private_note`) match exactly as they do on request params. *(F3)*
- **REQ-8.** The system shall apply this path-preserving filter to local variables and instance
  variables, for String, Symbol, Regexp and Proc filter patterns.
- **REQ-9.** Before a capture payload crosses the Active Job queue boundary, the system shall
  redact every context key that `ErrorContext#extract_params` can fold into `request_params` —
  including `:params`, `:additional_context`, `:metadata` and job/sidekiq-derived params — not
  only the already-covered `:request_params`. *(F4a)*
- **REQ-10.** Where capture tracing is enabled, the system shall redact the exception message
  with the same policy as storage before placing it on a span attribute, honoring
  `filter_sensitive_data`. *(F4b)*
- **REQ-11.** The redaction applied at the queue and export boundaries shall be the same policy
  applied at the storage boundary; no boundary shall expose what another redacts.

### C. Event-time and attribution truth (P3)

- **REQ-12.** The system shall record a storm-shed event's volume against the **hour bucket in
  which the event occurred**, not only against a lifetime group counter. *(F5, prerequisite)*
- **REQ-13.** Time-window volume figures (`total_today`, `total_week`, `total_month`, daily
  trend, hour-of-day, error rate, spike detection, top errors, by-severity/type/platform/
  environment) shall count events whose **own** timestamp falls in the window, independent of
  when the group was first seen. *(F5)*
- **REQ-14.** Window volume shall be computed from occurrence rows **plus** bucketed storm-shed
  counts, so that a group with no occurrence rows still contributes its volume.
  *(Non-negotiable: `spec/queries/analytics_event_counting_spec.rb:137-151` asserts a
  250-count row with zero occurrence rows reports 250. A pure `COUNT(*)` over occurrences is
  a regression, not a fix.)*
- **REQ-15.** Group-scoped metrics (`total_groups`, `unresolved`, `resolved`, new-groups) shall
  remain group-scoped and shall be labelled as such; "groups first seen in this window" is a
  legitimate separate metric, not a replacement.
- **REQ-16.** Per-user event counts shall be derived from occurrence rows for any group that has
  occurrence coverage in the window; the group-level fallback shall apply **only** to groups
  with no occurrence coverage. *(F6)*
- **REQ-17.** The sum of per-user counts shall never exceed the window's total event count, and
  any figure that is a lower bound shall continue to be reported as incomplete.
- **REQ-18.** When a capture is enqueued for async processing, the system shall stamp the
  envelope with the capture-time `occurred_at`, `app_version` and `git_sha`, and the worker
  shall persist those stamped values rather than reconstructing them from `Time.current` and
  its own process configuration. *(F7)*
- **REQ-19.** The system shall preserve a separate ingestion time, so queue lag remains
  observable.

### D. Provenance and input honesty (P4)

- **REQ-20.** The system shall not label a snapshot as a fresh, `full`-fidelity capture when it
  is a mixture of fields from different occurrences; `context_captured_at` and
  `context_fidelity` shall describe only what the current occurrence actually supplied. *(F9)*
- **REQ-21.** The system shall represent "known anonymous" distinguishably from "user
  information unavailable". *(F9)*
- **REQ-22.** Where `ManualErrorReporter` documents `occurred_at:`, `app_version:`,
  `metadata:` and `severity:`, the system shall either retain those values or reject the input
  explicitly; it shall not silently discard a documented parameter. *(F8)*
- **REQ-23.** If a caller-supplied `occurred_at` is in the future, then the system shall clamp
  it to the current time.
- **REQ-24.** A caller-supplied `occurred_at` shall not be allowed to create a group that falls
  outside the 24-hour grouping window and is therefore permanently unmatchable
  (`design.md` §D6).
- **REQ-25.** When an async capture carries an error type the worker cannot constantize, the
  system shall preserve the serialized type name rather than substituting `StandardError`. *(F8)*
- **REQ-26.** The documentation shall describe raise-time variable capture as a **one-level**
  snapshot: strings, arrays and hashes copied one level deep at raise time, nested containers
  and other objects remaining references that show their state at serialization time. *(F10)*

### E. Bounded work and mobile layout (P5)

- **REQ-27.** Where the serializer encounters an object of unknown type, it shall produce a safe
  structural summary rather than invoking arbitrary `#inspect`, unless that type is explicitly
  opted in. *(F12)*
- **REQ-28.** Where `#inspect` is invoked, the system shall bound it with a wall-clock budget and
  degrade to a safe summary when the budget is exceeded, logging at debug level.
- **REQ-29.** The opt-in allowlist shall include the types the current specs depend on (Struct,
  ActiveModel) so that safe-by-default does not silently change documented behavior. *(F12)*
- **REQ-30.** At viewport widths below the desktop breakpoint, the error detail page shall not
  scroll horizontally: `document.scrollWidth` shall equal the viewport width at 390px. *(F13)*
- **REQ-31.** At phone widths the hero action row shall wrap to its own line rather than
  compressing the title column, and the error type shall render on one line where it fits.
- **REQ-32.** Desktop layout above the breakpoint shall be visually unchanged.
- **REQ-33.** A background job that fails outside an HTTP request shall have its own breadcrumb
  buffer, and the stored error's `breadcrumbs` shall be populated. *(F11)*
- **REQ-34.** Breadcrumb buffer initialization shall be nesting-aware: a job performed inline
  within a request shall not erase or prematurely clear the surrounding request's buffer.
- **REQ-35.** Job breadcrumb capture shall not cause the async path to double-harvest
  breadcrumbs (`design.md` §D7).

## Non-functional constraints

These bind every task. They come from `host-app-safety` and are not negotiable.

- **NFR-1.** No change may introduce a `raise` into the capture path except re-raising the
  caller's original exception (Safety Rule 1, Rule 5). REQ-4's abort raises *inside* the flush
  job's own transaction, which is the job's path, not the host request path.
- **NFR-2.** Total capture stays within the <5ms budget; the breadcrumb callback within
  <0.01ms. REQ-27/28 must **reduce** worst-case capture cost, never raise the typical case.
- **NFR-3.** Any new thread-local state is cleaned in an `ensure` (Rule 4).
- **NFR-4.** Every new request-path behavior is disableable by config (Rule 7).
- **NFR-5.** New compound indexes are named explicitly, never auto-generated (Mailboxer #480).
- **NFR-6.** Any new query that could touch unbounded rows must aggregate in SQL or `pluck` the
  needed columns — never load rows to count them in Ruby.
- **NFR-7.** All four adapters stay supported: PostgreSQL, MySQL, SQLite. The new rollup table's
  upsert must be adapter-portable (`design.md` §D4).

## Acceptance

Done means: every REQ above has a task in `tasks.md` and a test that fails before the change and
passes after; the full suite (~5,009 examples) and the browser suite (141) stay green; RuboCop
and `bin/i18n-check` pass; and the reviewer's own probe specs in `review-evidence/2026-09-19/`
(T1–T13, C1, P1, P2) flip from failing to passing where they encode a requirement above.

Adopting the reviewer's probes as regression tests is an explicit goal — they are the
independent statement of these contracts, and the existing suite passed 5,009 examples while
every one of these defects was live.
