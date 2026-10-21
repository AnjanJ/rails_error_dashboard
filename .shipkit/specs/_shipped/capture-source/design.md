# Design: Capture source

## Approach
- **Two new nullable columns:**
  - `error_occurrences.capture_source` records how each occurrence was captured: `"server"` or
    `"client"`.
  - `error_logs.backtrace_source` records where the backtrace the error page shows came from. It
    is set when the row is created and whenever `backtrace_upgrade` replaces the backtrace.
- **The predicate:** `ErrorLog#client_backtrace?` (`backtrace_source == "client"`). The three
  readers check it before they touch a file: View Source, git blame, and
  `MarkdownErrorFormatter`, which feeds both Copy for LLM and AI help.
- **Old rows:** `nil` means server, so rows from before 0.16.0 keep today's behaviour (REQ-7).

## Decision: record the source per occurrence and per shown backtrace   (→ REQ-1, REQ-2, REQ-4)

**Context.**
- A group could hold occurrences from both sources.
- The page shows one stored backtrace, the one `backtrace_upgrade` last wrote
  (`find_or_increment_error.rb:222-240`).
- A multi-line backtrace is never replaced. So a client report that arrives first keeps its
  backtrace for the life of the group, and a server capture can replace a one-line client
  backtrace.

**Alternatives.**
1. `capture_source` on occurrences plus `backtrace_source` on the error row.
2. A single `capture_source` on the error row only.
3. Occurrences only, with the page working out which occurrence supplied the backtrace.

**Case for 1.**
- REQ-1 and REQ-2 hold for every capture.
- The reader gate follows exactly the backtrace the page shows, with no inference.
- Nothing is overwritten ambiguously.

**Case against 1.** Two columns and two writes instead of one. `backtrace_source` must be kept
in step at every place the backtrace is written: create, `backtrace_upgrade`, crash import and
the storm exemplar.

**Decision.** Option 1.

**Amended in T3.** The storm exemplar is not always `"server"`. Storm protection runs inside
`LogError.call`, so it counts `ManualErrorReporter` reports too. Its exemplar's
`first_app_frame`, which becomes the minimal row's backtrace, is then the frame a client sent. The
gate therefore records the event's source in its parts (`gate.rb#gate_parts`), outside the
identity and the gate key. The count buffer carries it (`CountBuffer::Entry`, the snapshot and
`parts_from`), and `FlushStormCounts` writes it to `backtrace_source`. A client event and a server
event of one error share an entry, and the entry keeps the first event's frame, so it keeps that
event's source. An entry from a release without the field reads as server (REQ-7). T3 gains
`storm_protection/gate.rb` and `storm_protection/count_buffer.rb`.

**Falsifiability.** We would fold both into the event envelope if the deferred envelope refactor
(evidence-integrity §D8) is specced and starts.
**Fired-if.** `test -f .shipkit/specs/event-envelope/spec.md`

## Decision: ManualErrorReporter sets the marker itself, after the caller's values   (→ REQ-1, REQ-2, REQ-7)

**Context.**
- `ManualErrorReporter` builds its own context hash from named arguments and never forwards a
  caller hash (`manual_error_reporter.rb:97-107`). Its caller is the host's endpoint, which
  relays client data.
- `LogError.call` is public and takes any context, but every direct caller is the host's own
  code, which is trusted.
- The threat is a client making its report look server-captured, never the reverse.

**Alternatives.**
1. An internal context key (`_capture_source: "client"`) that `ManualErrorReporter` sets last.
   `LogError` reads it and treats a missing key as server. It travels in the async payload like
   the other `_serialized_*` keys.
2. A separate internal entry point (`LogError.call_client_report`) plus a dedicated ActiveJob
   argument.

**Case for 1.**
- No client-controlled argument can set or clear the key: `source:` and `metadata:` go elsewhere.
- It survives the async path unchanged, since `redact_async_payload` only touches named keys.
- It needs no new plumbing through the job.

**Case against 1.** App code calling `LogError.call` directly could set the key. That code is
trusted, and could just as well call `ManualErrorReporter`, but the key is undocumented API.

**Decision.** Option 1. The caller's `source:` string is still never used for this.
**Falsifiability.** We would switch to a separate entry point if any capture path starts
forwarding a caller-supplied context hash into `LogError` (for example, a `context:` option on
`ManualErrorReporter.report`).
**Fired-if.** manual

## Decision: one predicate on ErrorLog, checked at each reader   (→ REQ-4, REQ-5, REQ-6)

**Context.**
- `read_source_code(frame)` and `read_git_blame(frame)` receive only the frame
  (`backtrace_helper.rb:204, 253`).
- `_error_info.html.erb:150` renders the source partial with `error` in scope.
- `MarkdownErrorFormatter#source_code_section` holds `@error` and calls `SourceCodeReader`
  directly. AI help sends that formatter's output (`errors_controller.rb:249`).

**Alternatives.**
1. `ErrorLog#client_backtrace?`, checked where each reader is entered:
   - `_error_info` renders neither the View Source toggle nor the source partial (so no blame),
     and shows a note instead
   - `source_code_section` returns nil
2. Pass the error into `SourceCodeReader` and gate inside it.

**Case for 1.**
- `SourceCodeReader` stays a pure file reader, keeping its 0.15.0 file rules.
- The two places that start reads are the two that can ask the question.
- The note tells users why View Source is missing.

**Case against 1.** A third, future reader of frame files would have to remember the check.

**Decision.** Option 1.
**Falsifiability.** We would move the gate into a shared reader taking the error if a third
`SourceCodeReader.new` call site appears.
**Fired-if.** `test "$(grep -rn 'SourceCodeReader.new' app lib | grep -v 'services/source_code_reader.rb' | wc -l)" -gt 2` <!-- the reader's own doc comment has an example call -->

## Data / interface changes
- **Migration** `add_capture_source_to_error_occurrences_and_error_logs`, guarded by
  `column_exists?`:
  - `error_occurrences.capture_source` (string, limit 10, null)
  - `error_logs.backtrace_source` (string, limit 10, null)
- Also `spec/dummy/db/schema.rb`. Neither column is in the fingerprint: `ErrorHashGenerator` and
  `opaque_identity` are untouched, following the environment-awareness precedent (→ REQ-3).
  (→ REQ-9)
- **Writes:**
  - `LogError` sets `attributes[:backtrace_source]` and the occurrence's `capture_source` from the
    marker.
  - `FindOrIncrementError#backtrace_upgrade` copies `backtrace_source` along with the backtrace.
  - Crash import writes `"server"`. The storm exemplar writes the source of the event it was
    built from (amended in T3, below).
  - Every write sits inside the existing rescues (REQ-8).
- **UI:** a note in place of View Source for client backtraces, with locale keys in all 11
  locales. Docs: SOURCE_CODE_INTEGRATION.md and its `_features` copy (REQ-10).
