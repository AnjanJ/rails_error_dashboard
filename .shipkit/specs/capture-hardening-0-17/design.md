# Design: Capture hardening for 0.17.0

## Approach
Three changes on the capture path, plus docs:
- **Limits, in a new `Services::CaptureLimits`** (no I/O, no state):
  - `message` shortens a message to 10,000 characters plus a marker;
  - `request_params` fits params into 64,000 bytes as valid JSON;
  - `ErrorLogsRecord.clamp_text_attributes` is the per-column net at 65,535 bytes, next to the
    existing `clamp_string_attributes`.
- **Filtering fails closed** inside `SensitiveDataFilter`. Every unexpected failure yields
  `[FILTERED]`. Text that isn't JSON gets the message rules. The message rules learn three more
  shapes.
- **The session digest** returns nil when the app has no secret.

The crash import, which bypassed both the filter and the limits, goes through them like every other
write.

## Decision: Limit before filtering, at each entry point, and clamp again at the write   (→ REQ-1, REQ-2, REQ-3, REQ-4, REQ-12)

**Context.** Messages and params reach the database by four routes:
- the sync capture (`LogError#call` builds the attributes);
- the async enqueue (`LogError.call_async` redacts the payload on the request thread);
- the storm gate (it buffers a redacted message on the request thread, but only the first 500
  characters, `HASH_MESSAGE_LIMIT`, so it is already bounded and needs no change);
- the crash import.

The filter's regexes and its `JSON.parse` run on whatever size arrives, on the request thread in
three of the four routes. Context payloads (breadcrumbs, locals, health) are added to the attributes
after filtering, and the same hash feeds both the error row and the occurrence-context row.

**Alternatives.**
1. Shorten the message and params where each route first takes them, before any filtering. Then run
   one per-column clamp on the final attributes just before they are written: in `LogError` before
   `find_or_increment_by_hash`, in `FlushStormCounts` before `create!`, and in the crash import.
2. One clamp in the model (`before_save`), covering every write.
3. Clamp only at the write, with no limits at entry.

**Case for 1.** The filter and `JSON.parse` only ever see bounded input, so their cost has a ceiling
on the request thread (the paramount budget). The final clamp catches anything that grew after
filtering, such as a big locals payload, and it covers the occurrence-context row too, because that
row is built from the same attributes.

The async route limits on the request thread and the worker limits again, so `CaptureLimits.message`
leaves a message it already cut alone.

**Case against 1.** There are more call sites to keep in step: three entry points and three write
points. A new route added later could forget the entry limit; the write clamp still saves the row,
but the regexes would run unbounded. Option 2 is one hook, but too late to bound the filter, and
model callbacks don't run for `insert_all`.

**Decision.** Option 1. The limits live in one service, so each call site is one line.
**Falsifiability.** We would move to a single choke point if a fifth route to the error tables is
added and the review that adds it misses the entry limit (a spec of that route storing an unbounded
message).
**Fired-if.** manual

## Decision: Message limit is 10,000 characters, with a marker   (→ REQ-1, REQ-5)

**Context.** The user chose limits at capture on 2026-10-22 and reworded the product non-goal to
allow per-field size limits. `CrashCapture` already keeps 10,000 characters of a crash message.
MySQL's TEXT holds 65,535 bytes. A GitHub issue body holds 65,536 characters.

**Alternatives.**
1. 10,000 characters plus `… [N more characters]`.
2. As many bytes as TEXT holds, about 64 KB.
3. 2,000 characters.

**Case for 1.** It matches the crash path. Even at 4 bytes per character it fits TEXT with room for
the marker. It is far longer than any message a person reads, and it keeps messages well inside
issue, Slack and AI-help limits. The fingerprint hashes only the first 500 characters of the raw
message, before this runs, so grouping can't change.

**Case against 1.** An exception that embeds a big payload in its message loses everything past
10,000 characters. Option 2 keeps more, but leaves messages large enough to break issue creation and
inflate AI-help prompts.

**Decision.** Option 1.
**Falsifiability.** We would raise the limit if an issue reports a real error whose cause sat past the
10,000th character of its message.
**Fired-if.** manual

## Decision: Over-size params keep valid JSON by dropping the largest values   (→ REQ-2)

**Context.** `request_params` is a JSON string. The detail page pretty-prints it when it parses and
shows the raw text when it doesn't (`_request_context.html.erb`). Large params are usually one big
value (a base64 upload, a rich-text body) beside small, useful ones.

**Alternatives.**
1. Parse it. While the JSON is over 64,000 bytes, replace the largest top-level value with
   `"[TRUNCATED]"` (largest first), then add `"_truncated": true`. A body that isn't a JSON object
   (an array, or not JSON at all) is cut by bytes at a UTF-8 boundary, with a marker.
2. Cut the string by bytes.
3. Replace the whole value with a marker.

**Case for 1.** The useful small fields survive, and the page still renders the params as JSON.
Dropping by size removes the fewest values for the bytes saved.

**Case against 1.** It parses up to 64 KB more than the old path did, and nested objects are treated
as one value, so a big nested blob takes its siblings with it. Option 2 is cheaper but leaves invalid
JSON that the page shows as raw text.

**Decision.** Option 1. The parse happens only when the params are over the limit.
**Falsifiability.** We would replace it with option 2 if the overhead benchmark shows this path above
the 5 ms capture budget for a 1 MB body.
**Fired-if.** manual

## Decision: A per-column net at 65,535 bytes on every adapter; JSON is dropped, text is cut   (→ REQ-3, REQ-4)

**Context.** MySQL in strict mode rejects an INSERT with a TEXT value over 65,535 bytes. The capture
path rescues the failure, so the error is lost. PostgreSQL and SQLite store any size. After the two
limits above, the remaining text columns (`backtrace`, `exception_cause`, `environment_info`,
`breadcrumbs`, `system_health`, `local_variables`, `instance_variables`, `user_agent`, `request_url`)
are bounded by their collectors in practice, but nothing guarantees it.
`clamp_string_attributes` already does this job for string columns.

**Alternatives.**
1. `ErrorLogsRecord.clamp_text_attributes`, beside `clamp_string_attributes`. For every text column
   whose value is over 65,535 bytes: a JSON column (a fixed list) is set to nil, and any other column
   is cut at a UTF-8 boundary with a marker. Same rule on every adapter.
2. Clamp only on MySQL, using the column's reported limit.
3. Cut JSON columns by bytes too.

**Case for 1.** One rule everywhere, so tests on SQLite prove what MySQL needs. A context payload
RED can't store is RED's own data to give up (the paramount rule), and the error row survives. Cutting
JSON would leave a payload the page can't parse.

**Case against 1.** On PostgreSQL and SQLite it now drops oversized context that used to be stored.
The JSON-column list must be kept in step with the schema. A new JSON column missing from the list
would be cut instead of dropped.

**Decision.** Option 1.
**Falsifiability.** We would revisit dropping JSON if an issue reports a context payload (locals,
breadcrumbs) missing because it exceeded 64 KB.
**Fired-if.** manual

## Decision: Fail closed per field; text that isn't JSON gets the message rules   (→ REQ-6, REQ-7, REQ-11, REQ-15)

**Context.** Each helper in `SensitiveDataFilter` rescues by returning its input. `filter_attributes`
returns the raw attributes when the filter can't be built or anything raises. `filter_json_string`
and `filter_cause_chain` return non-JSON input as it came. The user decided on 2026-10-22 that
filtering fails closed. The crash import never calls the filter at all.

**Alternatives.**
1. Every unexpected exception yields `[FILTERED]` for that field. A filter that can't be built yields
   `[FILTERED]` for each of the four fields present. A JSON parse failure is not a filter failure:
   that text goes through the message rules. The crash import calls `filter_attributes` and the
   limits.
2. Replace non-JSON params with `[FILTERED]` too.
3. Fail closed only at the top level of `filter_attributes`.

**Case for 1.** A secret never reaches the database because a step broke, and useful non-JSON text
(a caller's pre-serialized params, a truncated body) is still redacted rather than thrown away. The
fingerprint is taken before filtering, so a `[FILTERED]` message doesn't change grouping.

**Case against 1.** A bug in the filter now blanks fields people need for debugging, where before it
leaked them. The existing spec "returns original attributes if filtering raises unexpectedly" pins
the old behaviour and is rewritten. Breadcrumbs and variable values that call `filter_message` also
become `[FILTERED]` when it raises.

**Decision.** Option 1. The 0.17.0 notes say filtering now fails closed.
**Falsifiability.** We would reconsider if an issue reports `[FILTERED]` replacing a field with no
secret in it, caused by a filter failure.
**Fired-if.** manual

## Decision: Three more message shapes, with linear patterns   (→ REQ-8, REQ-9, REQ-10, REQ-12)

**Context.** `filter_message` handles `(\w+)=(\S+)` and card numbers. The common shapes that leak
today are `key: value`, JSON pairs (`"key":"value"`, as in `JSON::ParserError` text) and
`Bearer <token>`. A URL whose query string `Rack::Utils.parse_query` can't parse (a stray `%`) is
stored whole. The filter decides which keys are sensitive (`ParameterFilter`, which can hold regexes
and procs from `filter_parameters`), so every candidate key has to be asked.

**Alternatives.**
1. Three more `gsub` passes, each with a pattern free of nested quantifiers:
   - `key: value`, where the value may be quoted;
   - `"key"\s*:\s*value`, where the value is a JSON string or a bare token;
   - `Bearer <token>`.

   Each candidate key is checked with the filter, as `key=value` already is. For URLs, the fallback
   after a parse failure applies the `key=value` pass to the query string.
2. One combined regex built from the sensitive pattern list.
3. Leave free text as it is, and only document the limits.

**Case for 1.** It reuses the filter's own decision for each key, so `filter_parameters`, custom
patterns and procs all apply. Every pattern is linear, and the message limit caps the input at 10,000
characters.

**Case against 1.** It is three more passes over every message, with one filter call per candidate
key. Text with many `word:` tokens costs more. A 50 ms ceiling on adversarial input is a guard
against catastrophic backtracking, not a budget, so the typical cost is measured in the task.
Option 2 is faster, but can't express procs.

**Decision.** Option 1. If the measured cost of a typical message is above 1 ms, add a small bounded
per-key memo.
**Falsifiability.** We would switch to option 2 if the overhead benchmark shows message filtering
above 1 ms for a typical (under 500-character) message.
**Fired-if.** manual

## Decision: No secret, no session ID   (→ REQ-14)

**Context.** `session_digest_key` falls back to the constant `"rails_error_dashboard"` when the app
has no `secret_key_base`. Rails 8 refuses to boot in production without one, so this matters only on
older Rails or unusual setups.

**Alternatives.**
1. `digest_session_id` returns nil when there is no secret.
2. A random per-process key.
3. Keep the constant.

**Case for 1.** It stores nothing guessable. The only loss is "these occurrences were one session",
and only for apps with no secret.

**Case against 1.** Session correlation disappears for those apps. Option 2 would keep it within a
process, but not across processes.

**Decision.** Option 1.
**Falsifiability.** We would revisit this if an issue reports session correlation missing on an app
that has a `secret_key_base`.
**Fired-if.** manual

## Data / interface changes
- New `Services::CaptureLimits` (`message`, `request_params`), and
  `ErrorLogsRecord.clamp_text_attributes`. No new configuration, no migrations.
- `SensitiveDataFilter`:
  - helpers return `[FILTERED]` on unexpected errors;
  - `filter_attributes` never returns the raw attributes when filtering is on;
  - `digest_session_id` returns nil without a secret.
- Docs: README, `docs/FEATURES.md`, `docs/guides/CONFIGURATION.md` and their site copies (grep the
  content) say message redaction is best-effort, and that filtering fails closed.

## Release notes (for the 0.17.0 notes, not a requirement)
- Errors with very long messages or request params were lost on MySQL. They are now stored, and on
  every adapter messages are kept to 10,000 characters and params to about 64 KB.
- Secret filtering now fails closed: if a filter step fails, the field is stored as `[FILTERED]`.
  Message redaction is best-effort.
