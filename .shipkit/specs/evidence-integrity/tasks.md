# Tasks: Evidence integrity sprint

Test first for every task: write the failing test, watch it fail **for the right reason**, then
fix. Run targeted specs, RuboCop and `bin/i18n-check` after each task; full suite +
`bin/pre-release-test all` before each PR.

**Environment (this machine).** Bare `bundle exec` fails — prefix everything:

```sh
cd /Users/anjan/code/RED/rails_error_dashboard
mise exec ruby@3.4.5 -- bundle exec rspec <path>
```

`spec/dummy/db/test.sqlite3` must exist (it is gitignored). If it is missing you get a
"disk I/O error" that looks like a sandbox denial but is self-inflicted — recreate it with
SQLite, not `touch`. A healthy full run is **~5,009 examples / ~72% coverage**, not 0/22%.

**Adapters.** PostgreSQL: set `DATABASE_URL` and run — no config change needed. MySQL needs a
temp trilogy Gemfile and a fresh DB. Several fixes below are only *observable* on PG/MySQL
(row locks are no-ops on SQLite), so P1 and P3 need a PG pass before their PR.

**Baseline.** Record the count before starting, so a drop is visible:

```sh
mise exec ruby@3.4.5 -- bundle exec rspec --exclude-pattern 'spec/system/**/*' --format progress
```

**Never** write `Fixes/Closes/Resolves #223` — it auto-closes the reporter's issue. Use
`Refs #223`.

---

## P1 — Storm count conservation (`fix:`)

Branch `fix/storm-count-conservation`. Files: `lib/rails_error_dashboard/commands/flush_storm_counts.rb`.

- [x] **T1.1** Failing spec: two concurrent storm batches of 5 against a resolved group starting
  at 1 → `occurrence_count == 11`. → REQ-1
  Put it in `spec/commands/flush_storm_counts_concurrency_spec.rb`. Two complementary forms —
  write **both**:
  - *Deterministic (runs everywhere, including SQLite).* Stub `update!` to interleave two real
    flushes between their SELECT and UPDATE. Reads, writes and transactions stay real; only
    scheduling is controlled. This reproduces the exact 6-instead-of-11 result and is the
    regression test that runs in normal CI.
  - *Threaded on PostgreSQL.* Model on the reviewer's P1 probe
    (`review-evidence/2026-09-19/postgresql_spec.rb`). Needed because `.lock` (`FOR UPDATE`) is
    a **no-op on SQLite** — only PG/MySQL can prove the fix actually serializes. Tag it to skip
    on SQLite with an explicit skip message, never a silent pass.
  Note the deterministic form needs both `DATABASE_URL` **and** `ERROR_LOGS_DATABASE_URL`
  pointed at a private copy, or the dummy app's two connections diverge and schema load fails
  on a foreign key.
- [x] **T1.2** Add `.lock` to the resolved-row read (`flush_storm_counts.rb:~199`,
  `resolved_scope.order(last_seen_at: :desc).lock.first`). Keep `update!`. → REQ-2, REQ-3
  **Do NOT switch this branch to `update_all`** — `ErrorLog` has
  `after_update_commit -> { ErrorBroadcaster.broadcast_update(self) }`
  (`app/models/rails_error_dashboard/error_log.rb:87`); `update_all` skips callbacks and would
  silently kill live updates on reopen. See `design.md` §D1.
- [x] **T1.3** Regression guard: assert the reopen still broadcasts. Without this, a future
  "consistency" refactor to `update_all` reintroduces the callback bug invisibly. → REQ-3
- [x] **T1.4** Confirm the existing reopen spec still passes unchanged:
  `spec/commands/flush_storm_counts_spec.rb:77-91` ("reopen semantics (mirrors
  FindOrIncrementError)") asserts `occurrence_count == 6`, `resolved == false`,
  `status == "new"`. All storm specs are single-threaded and assert post-conditions only, so
  none encodes the racy behavior — verified by grep for `Thread|\.lock|concurren` (0 hits) in
  `flush_storm_counts_spec.rb`, `storm_batch_idempotency_spec.rb`, `wont_fix_sticky_spec.rb`.
- [x] **T1.5** Failing spec: a batch of two 5-event entries where the **second** raises a
  transient `ActiveRecord::ConnectionNotEstablished` → nothing is committed, the ledger is
  **not** claimed, replay reconciles all 10. → REQ-4
  Model on the reviewer's T8 probe.
- [x] **T1.6** Change the per-entry rescue (`:57-66`) to re-raise
  `Commands::LogError::RETRYABLE_STORE_ERRORS` out of the transaction block so the whole batch
  rolls back; keep the generic `rescue => e` skip-and-continue below it for malformed entries.
  → REQ-4, REQ-5. The constant already exists at `log_error.rb:15` and is already used for
  retry decisions at `:602` — reuse it, do not redefine "transient".
- [x] **T1.7** Report the two classes distinguishably in the return value (e.g. `failed:` for
  permanent skips vs. an aborted/retryable result for transient). → REQ-6
- [x] **T1.8** Confirm unchanged: `flush_storm_counts_spec.rb:289` ("still reports success when
  some entries reconciled") and `storm_flush_job_spec.rb:96` both use a *permanently* bad entry
  (`{"count" => 5}`, no identity) which still falls to the generic rescue —
  they must stay green. `storm_batch_idempotency_spec.rb:69-83` guards only the all-fail case.
- [x] **T1.9** PostgreSQL pass for the whole file, then RuboCop. PR: "fix: conserve storm counts
  under concurrent reopen and transient batch failure (Refs #223)".

---

## P2 — Redaction boundary parity (`fix:`) — **security-relevant, ship early**

Branch `fix/redaction-boundary-parity`. Files: `services/variable_serializer.rb`,
`commands/log_error.rb`.

- [x] **T2.1** Failing spec: with `filter_parameters = ["profile.private_note"]`, a captured
  local `profile = { private_note: "SECRET", public: "ok" }` → `private_note` is `[FILTERED]`,
  `public` survives. → REQ-7
  Existing `variable_serializer_spec.rb` covers only **flat** names (`user_password`,
  `auth_token`, `api_key`) — the dotted path is the untested gap that let this ship.
  Minimal standalone proof of the mechanism:
  ```ruby
  f = ActiveSupport::ParameterFilter.new(["profile.private_note"])
  f.filter({"profile" => {"private_note" => "S"}})  # => [FILTERED]  (Rails' view)
  f.filter({"private_note" => "S"})                 # => "S"         (what RED passes)
  ```
- [x] **T2.2** In `filter_serialized` (`variable_serializer.rb:~197`), filter each value while
  still wrapped under its own name: `filter.filter(var_name => info[:value])[var_name]`; thread
  `parent_keys:` through `filter_hash_recursive` / `filter_array_recursive`. → REQ-7
  Use `ParameterFilter` itself — do not hand-roll dotted matching, or Proc filters break
  (`design.md` §D3).
- [x] **T2.3** Extend coverage to instance variables and to String/Symbol/Regexp/Proc patterns.
  → REQ-8
- [x] **T2.4** Failing spec: `LogError.call(..., params: { password: "X" })` with async
  enabled → the **enqueued job arguments** contain no raw password. → REQ-9
  The existing `spec/commands/log_error_queue_redaction_spec.rb` passes only the allowlisted
  `request_params:` form (`:49`, `:73`), which is exactly why the `params:` form leaked.
- [x] **T2.5** In `redact_async_payload` (`log_error.rb:~248`, after the existing merges at
  `:271-272`), redact every context key `ErrorContext#extract_params` can fold into
  `request_params`: `:params`, `:additional_context`, `:metadata`, and job/sidekiq-derived
  params. → REQ-9, REQ-11
  `SensitiveDataFilter.parameter_filter` is public (`sensitive_data_filter.rb:102`) and
  `ParameterFilter#filter` takes a Hash directly. `filter_json_string` is **not** reusable here
  — it expects a JSON string.
- [x] **T2.6** Failing spec: with tracing enabled, a message containing `password=SECRET` →
  the span attribute is redacted. → REQ-10
- [x] **T2.7** In `build_capture_span_attributes` (`log_error.rb:81-91`), redact **before**
  truncating, via `Services::SensitiveDataFilter`, honoring `filter_sensitive_data`. → REQ-10
  `filter_attributes` already returns input unchanged when filtering is off and has its own
  internal rescue.
- [x] **T2.8** Confirm unchanged: `spec/commands/log_error_otel_spec.rb:106-118` asserts
  `error.message` starts with "boom — capture me" and truncates to ≤201 chars. Both stay green
  (neither message contains a sensitive key); the proposed change was checked against invalid
  UTF-8 input and does not raise.
- [x] **T2.9** `spec/commands/log_error_spec.rb:115-133` passes `additional_context:` with
  benign keys and runs sync — verify it stays green (the filter leaves that hash identical).
- [x] **T2.10** Cross-boundary invariant spec: one capture, three boundaries (DB row, enqueued
  payload, span attribute) → the same secret absent from all three. → REQ-11
  This is the test that would have caught all three sub-findings at once.
- [x] **T2.11** Full suite + RuboCop. PR: "fix: apply one redaction policy at storage, queue and
  export boundaries (Refs #223)".

---

## P3 — Event time and attribution (`feat:` + `fix:`) — **largest; sequence carefully**

Branch `fix/event-time-windows`. Migration first, query cutover second (`design.md` §D4).

### Prerequisite: give shed volume a timestamp

- [x] **T3.1** Migration `create_event_counts`:
  `rails_error_dashboard_event_counts(error_log_id, bucket_at, count)`, unique on
  `(error_log_id, bucket_at)`. → REQ-12
  **Name the compound index explicitly** — auto-generated names blow PostgreSQL's 63-char limit
  and fail during the *host app's* deploy (Mailboxer #480, NFR-5). Update
  `spec/dummy/db/schema.rb` by **generating** it with the dumper from this repo's bundle —
  Rails 8.1 orders alphabetically and hand edits have drifted twice. Migration timestamp must
  not be in the future.
- [x] **T3.2** `Services::StormProtection::CountBuffer` keys tallies by **hour bucket** as well
  as error identity (today it carries only `first_seen_at`/`last_seen_at`). → REQ-12
  Respect the existing read/write lock on buffer handoff; do not widen the lock's scope.
- [x] **T3.3** `FlushStormCounts` upserts into `event_counts`
  (`INSERT … ON CONFLICT (error_log_id, bucket_at) DO UPDATE SET count = count + N`).
  → REQ-12. **Adapter-portable**: PG/SQLite `ON CONFLICT`, MySQL `ON DUPLICATE KEY UPDATE`
  (NFR-7). Must be inside the same transaction as the count increment, or a crash between them
  desynchronizes the two numbers.

### Window volume primitive

- [x] **T3.4** Failing spec: error at 23:59, recurrence at 00:01 → `total_today == 1`,
  yesterday `== 1`. → REQ-13. This is the reviewer's T1; reproduce it on **both** SQLite and PG.
- [x] **T3.5** Add `Queries::EventVolume.in_window(scope, from, to = nil)` returning
  `occurrence rows in window + shed buckets in window`. → REQ-13, REQ-14
  **Do NOT implement this as `COUNT(*)` over `ErrorOccurrence`.**
  `spec/queries/analytics_event_counting_spec.rb:137-151` creates a group with
  `occurrence_count: 250` and **zero** occurrence rows and asserts `total_today`,
  `top_errors["StandardError"]` and `errors_trend_7d.values.sum` all equal 250. Storm-shed
  events write no occurrence row by design. A pure count turns three assertions red and erases
  storm volume. Also guarded: `:86-95` (`error_rate == 400.0` from a bare 4,000-count row) and
  `:123-135` (`affected_users_incomplete` true for a bare 500-count row).
  Aggregate in SQL; never load rows to count them (NFR-6).
- [x] **T3.6** Route every window figure through it — `dashboard_stats.rb`: `event_count_since`
  (`:120-122`), `event_count_between` (`:125`), `total_today` (`:30`), `total_week`/`total_month`
  (`:31-32`), `top_errors` (`:163`), `errors_trend_7d` (`:170-175`), `errors_by_severity_7d`
  (`:179+`), `spike_detected?`/`spike_info` (`:219`, `:227`), `error_rate` (`:283-291`);
  `analytics_stats.rb`: `base_query` (`:63-65`), `event_count` (`:86-88`), `by_day` (`:79`),
  `errors_over_time` (`:90-92`), `errors_by_type`, `errors_by_platform`,
  `errors_by_environment`, `errors_by_hour` (`:113-118`). → REQ-13
  Trends group by `DATE(occurrences.occurred_at)` with shed buckets merged in — not
  `group_by_day(:occurred_at)` on `ErrorLog`.
- [x] **T3.7** Leave `total_groups`, `unresolved`, `resolved` and other group-scoped metrics
  alone; add `new_groups_in_window` if the first-seen figure is wanted on the page. → REQ-15
  `analytics_stats.rb:67-73` already documents this distinction — extend that comment.
- [x] **T3.8** Note: `dashboard_stats_spec.rb:10-14` fixtures set each group's `occurred_at`
  directly to the intended day, so first-seen always equals event day and the defect is
  structurally invisible there. Those specs stay green; add cross-midnight fixtures rather than
  editing them.

### Attribution

- [x] **T3.9** Failing spec: occurrences `{A:2, B:1}` → analytics reports `{A:2, B:1}`, and the
  per-user sum ≤ window total. → REQ-16, REQ-17 (reviewer's T3)
- [x] **T3.10** In `analytics_stats.rb#user_event_counts` (`:142`), apply `group_user_counts`
  **only** to groups with no occurrence coverage in the window — replace the
  `merge { max(group, occurrence) }`. Set `incomplete` for partially-covered groups. → REQ-16,
  REQ-17. See `design.md` §D5 for why `max` and "attribute the remainder" were both rejected.
- [x] **T3.11** ~~Mirror the same fix in `UserImpactSummary`~~ — **verified not needed.** Its
  merge is over DISTINCT USER counts, not event sums, so it cannot inflate the same way.
  Probed live: 2 users / 3 events, already correct. Left unchanged deliberately.

### Async envelope

- [x] **T3.12** Failing spec: capture at 12:00 under v1, run the job at 14:00 under v2 → stored
  `occurred_at == 12:00`, release `== v1`. → REQ-18 (reviewer's T2)
  No existing spec pins this: `async_logging_spec.rb` has 28 examples and asserts neither field
  — that gap is why it shipped.
- [x] **T3.13** In `LogError.call_async`, stamp `_captured_at`, `_app_version`, `_git_sha` onto
  the context beside the existing `_identity` merge (`:~137`), mirroring the `resolve_environment`
  idiom at `:680-685`. → REQ-18
- [x] **T3.14** In the persist path, prefer the stamped values over `Time.current` (`:387`) and
  over the current process's git/version lookups (`:426-437`); keep a separate ingestion time.
  → REQ-18, REQ-19
- [x] **T3.15** Run on PostgreSQL. Full suite + RuboCop. PR: "feat: count events in the window
  they occurred, and stamp async captures at capture time (Refs #223)".

---

## P4 — Provenance and input honesty (`feat:` + `fix:`) — follows P1

Branch `fix/snapshot-provenance`. Files: `commands/find_or_increment_error.rb`,
`value_objects/error_context.rb`, `manual_error_reporter.rb`,
`app/jobs/.../async_error_logging_job.rb`, docs.

- [x] **T4.1** Failing spec: event 1 (user 10, `/first`, locals), event 2 one minute later
  (anonymous, `/anonymous`, no locals) → the group is **not** labelled fresh `full` fidelity
  with event 2's timestamp while showing event 1's user and locals. → REQ-20 (reviewer's T4)
- [x] **T4.2** In `find_or_increment_error.rb`, make provenance reflect **completeness**, not
  presence: distinguish a whole-snapshot refresh from a partial one (`context_provenance` at
  `:140` and the `||` chain in `increment_existing` at `:202-206` are both halves of the
  mechanism). → REQ-20
  **Trap:** a `whole_snapshot_refreshed?` helper that calls `error.public_send(k)` over a list
  including `:instance_variables` collides with Ruby's `Object#instance_variables`. The
  ActiveRecord attribute method currently wins, but this is one `ignored_columns`/load-order
  change from silently comparing an Array. Use `read_attribute` explicitly.
- [x] **T4.3** Represent "known anonymous" distinctly from "user unavailable". → REQ-21
- [x] **T4.4** Confirm `spec/commands/snapshot_provenance_spec.rb` (the only file referencing
  `context_fidelity`/`context_captured_at`, 7 examples) still passes — run it scoped with
  `--example "diagnostic snapshot provenance"`; an unscoped single-file run pulls the whole
  suite via the helper's broad pattern.
- [x] **T4.5** Failing spec: `ManualErrorReporter` with `occurred_at:`, `app_version:`,
  `metadata:` → all retained. → REQ-22
  `manual_error_reporter_spec.rb:59-73` already *passes* these values but asserts only
  error_type/message/platform/user_id/request_url/user_agent/ip_address — the assertion gap
  that hid this.
- [x] **T4.6** `ErrorContext` learns `occurred_at` and `app_version` readers; merge `metadata`
  into params beside `additional_context`. → REQ-22
  **Critical:** add both to `to_h` — `error_context.rb:33-37` documents that exact hop as the
  trap that previously lost `request_id`/`session_id`.
- [x] **T4.7** Clamp `occurred_at`: reject future values (REQ-23) **and** keep the *group's*
  `occurred_at` inside the 24-hour grouping window while preserving the true time on the
  occurrence (REQ-24). `find_unresolved` matches on `where("occurred_at >= ?", 24.hours.ago)`
  (`find_or_increment_error.rb:80-88`) and `new_record_attributes` (`:244-256`) writes the
  incoming value onto the new row — so an unclamped backdated report creates a permanently
  unmatchable group. See `design.md` §D6.
- [x] **T4.8** **Reject `severity:` explicitly** and document why: it is not a column;
  `ErrorLog#severity` is computed by `Services::SeverityClassifier` from `error_type`
  (`app/models/rails_error_dashboard/error_log.rb:182-185`). → REQ-22
- [x] **T4.9** Failing spec: async capture of an unknown type `FrontendWidgetFailure` → stored
  `error_type` is preserved, not `StandardError`. → REQ-25 (reviewer's T9)
- [x] **T4.10** In `async_error_logging_job.rb:~67`, keep the serialized type name independently
  of constantizing a Ruby class. → REQ-25
- [x] **T4.11** Docs: describe raise-time capture as a **one-level** snapshot. → REQ-26
  The overstated claim lives in **four** places — all four must change together, or the fix is
  cosmetic:
  - `docs/GLOSSARY.md:437` — "at the exact moment an exception is raised"
  - `docs/FEATURES.md:745` — "you see exactly what the variables contained"
  - `docs/guides/CONFIGURATION.md:890` — "at the exact moment an exception is raised"
  - `_guides/configuration.md:856` — same sentence, in the Jekyll mirror
  **Grep the sentence text, not the filename.** `_guides/` is a hand-maintained lowercase mirror
  of `docs/guides/` that drifts and that filename searches miss — this is the known trap in this
  repo, and it is why the copies at `docs/guides/` and `_guides/` are easy to miss. Verify with:
  ```sh
  grep -rn "exact moment\|exactly what" docs/ _guides/ README.md | grep -i "variable\|raise"
  ```
  Suggested replacement wording: "Strings, arrays and hashes are copied one level deep at raise
  time; nested containers and other objects remain references and show their state at
  serialization time."
- [x] **T4.12** Full suite + RuboCop + `bin/i18n-check`. PR: "fix: label snapshot provenance
  honestly and retain documented manual-report fields (Refs #223)".

---

## P5 — Bounded work, job breadcrumbs, mobile layout (`feat:` + `fix:`) — independent

Branch `fix/bounded-serialization-and-mobile`.

### Job breadcrumbs

- [x] **T5.1** Failing spec: a real job via `ActiveJob::Base.execute` runs SQL and raises →
  stored `breadcrumbs` is populated. → REQ-33 (reviewer's T13)
  Note `breadcrumb_subscriber_spec.rb` does `before { collector.init_buffer }` at `:8-11`, so
  **every** existing example runs with a buffer already open — the out-of-request case is never
  exercised today.
- [x] **T5.2** `BreadcrumbCollector.init_buffer_unless_present` returning an ownership boolean;
  clear only when owned. → REQ-34
- [x] **T5.3** `ActiveSupport.on_load(:active_job)` `around_perform` in `engine.rb`, gated on
  `configuration.enable_breadcrumbs` (NFR-4), opening/closing via the ownership flag in an
  `ensure` (NFR-3). → REQ-33, REQ-34
- [x] **T5.4** Spec: a job performed **inline inside a request** does not erase the request's
  buffer; its SQL joins the surrounding trail. → REQ-34
- [x] **T5.5** Guard the async double-harvest: `log_error.rb:460-469` harvests the **current
  thread first** and only falls back to `@context[:_serialized_breadcrumbs]` when empty. With a
  worker-side buffer now open, the worker's own crumbs would shadow the request's. Prefer the
  serialized envelope when present. → REQ-35. Spec this interaction directly (`design.md` §D7).

### Bounded serialization

- [x] **T5.6** Failing spec: an object whose `inspect` sleeps and allocates → serialization stays
  within budget and yields a safe summary. → REQ-27, REQ-28 (reviewer's T12)
- [x] **T5.7** In `serialize_object` (`variable_serializer.rb:179-185` — the review's `:159`
  cite is the circular-reference guard, not the `inspect` call), replace unconditional
  `value.inspect` with a safe structural summary plus an opt-in allowlist and a wall-clock
  budget via `Process.clock_gettime(Process::CLOCK_MONOTONIC)`; degrade and log at debug on
  overrun. → REQ-27, REQ-28
  There is a **second** `value.inspect` at `:101` — leave it alone. It is `Regexp#inspect`, a
  bounded built-in reached from an explicit `when Regexp`. Only the `else` branch routes unknown
  objects into `serialize_object`, and that is the unbounded path.
- [x] **T5.8** Allowlist Struct and ActiveModel. → REQ-29
  **Breakage if skipped:** `variable_serializer_spec.rb:385-390` ("handles Struct objects via
  inspect fallback") asserts the value includes `"Alice"` — real `inspect` output. Either
  allowlist Struct or change that spec deliberately, never incidentally.
  `:392-397` ("object whose inspect raises") shows the author guarded *exceptions* from
  `inspect` but not *latency* — that is the gap.
- [x] **T5.9** New config: `local_variable_inspect_budget_ms`, `local_variable_inspect_allowlist`
  (NFR-4), documented in the changelog as a behavior change (`design.md` §D10).

### Mobile layout

- [x] **T5.10** Failing system spec at 390px on the error **detail** page: `scrollWidth ==
  innerWidth`. → REQ-30
  `spec/system/p7_layout_qa_spec.rb` visits only `/errors`, `/overview`, `/errors/analytics`,
  `/settings` — `visit_error` appears nowhere, so the detail page is never rendered at any
  width. That structural blindness is why this shipped. Add the detail page to its loops.
- [x] **T5.11** Replace the hero's inline flex (`show.html.erb:16`, `:17`, `:81`) with layout
  classes carrying a breakpoint:
  ```css
  .red-error-hero { display:flex; flex-wrap:wrap; align-items:flex-start;
                    justify-content:space-between; gap:var(--space-4); }
  .red-error-hero-text { flex:1 1 260px; min-width:0; }
  .red-error-hero-actions { display:flex; flex-wrap:wrap; gap:6px; }
  ```
  → REQ-31, REQ-32
  The load-bearing parts: `flex: 1 1 260px` (**not** `flex: 1`) stops the text column collapsing
  toward zero, and **dropping `flex-shrink: 0`** from the actions row (`:78`) lets up to five
  buttons wrap to their own line instead of crushing the title to one character per line.
- [x] **T5.12** The horizontal overflow (448px vs 390px) is a **separate** cause from the hero
  squeeze — the review conflated them. Identify and constrain the actual overflowing element
  (detail tables whose header labels cannot fit); let them wrap or scroll within their own
  container, never widen the page. → REQ-30
- [x] **T5.13** Verify desktop above the breakpoint is visually unchanged. → REQ-32
  No spec asserts hero structure (grepped `flex-shrink`, `red-error-hero`, `hero-assign-btn`:
  0 hits). `errors_show_i18n_spec.rb:24` and `spec/support/modal_helpers.rb:59` are content
  assertions and are unaffected by moving inline styles into classes.
- [x] **T5.14** Browser suite (141 examples) + full suite + RuboCop + `bin/i18n-check`.
  PR: "fix: bound serialization work, collect job breadcrumbs, and fix phone-width detail page
  (Refs #223)".

---

## Close-out

- [ ] **T6.1** Run the reviewer's probes (`review-evidence/2026-09-19/boundary_spec.rb`,
  `postgresql_spec.rb`, `visual_spec.rb`) and record which flip to passing. They are the
  independent statement of these contracts — the existing 5,009 examples passed while every one
  of these defects was live.
- [ ] **T6.2** Promote the probes that encode a requirement into `spec/` as permanent regression
  tests, credited to the review.
- [ ] **T6.3** Full matrix: `bin/pre-release-test all`, plus a PostgreSQL and a MySQL pass.
- [ ] **T6.4** Changelog upgrade notes: the `event_counts` migration, and the serializer default
  change with its new config options.
- [ ] **T6.5** Write `.shipkit/specs/event-envelope/` — the deferred refactor (`design.md` §D8)
  — while the findings are fresh, citing the invariants added here as its acceptance harness.
- [ ] **T6.6** Comment on **#223** with root causes and the shipping version. Do **not** close it
  — the reporter closes it. Check no PR body or commit used a closing keyword.
- [ ] **T6.7** File the demo-app `GET /admin/seed` issue against
  `rails_error_dashboard_demo_app` (destructive seeding behind publicly-documented demo
  credentials; move to an operator-only command or an authorized POST). Out of scope here.
- [ ] **T6.8** **Stop. Ask before merging the release PR** — that merge is the publish action
  and is irreversible for that version number. Expected: **0.14.0** (the `feat:` commits in P3,
  P4 and P5 drive the minor bump).

---

## Traceability

| REQ | Task(s) | PR |
|---|---|---|
| REQ-1..3 | T1.1–T1.4 | P1 |
| REQ-4..6 | T1.5–T1.8 | P1 |
| REQ-7, REQ-8 | T2.1–T2.3 | P2 |
| REQ-9 | T2.4, T2.5 | P2 |
| REQ-10 | T2.6–T2.8 | P2 |
| REQ-11 | T2.5, T2.10 | P2 |
| REQ-12 | T3.1–T3.3 | P3 |
| REQ-13, REQ-14 | T3.4–T3.6 | P3 |
| REQ-15 | T3.7 | P3 |
| REQ-16, REQ-17 | T3.9–T3.11 | P3 |
| REQ-18, REQ-19 | T3.12–T3.14 | P3 |
| REQ-20, REQ-21 | T4.1–T4.4 | P4 |
| REQ-22, REQ-23, REQ-24 | T4.5–T4.8 | P4 |
| REQ-25 | T4.9, T4.10 | P4 |
| REQ-26 | T4.11 | P4 |
| REQ-27, REQ-28, REQ-29 | T5.6–T5.9 | P5 |
| REQ-30, REQ-31, REQ-32 | T5.10–T5.13 | P5 |
| REQ-33, REQ-34, REQ-35 | T5.1–T5.5 | P5 |
