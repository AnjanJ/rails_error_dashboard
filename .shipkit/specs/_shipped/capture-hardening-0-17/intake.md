# Intake: capture hardening for 0.17.0

> Intake taken on 2026-10-22.

## Request
Harden what the capture path stores, for 0.17.0:
1. On MySQL in strict mode (its default), an error whose message or request params exceed 64 KB is
   silently lost. On other adapters they are stored unbounded.
2. Secret filtering fails open: if a filter step raises, or the filter can't be built, the raw value
   is stored. Message redaction only recognises `key=value`.
3. The session-ID digest falls back to a constant key when the app has no `secret_key_base`.

## Serves goal
"Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen". 0.17.0 is the
release before 1.0.0.rc1 (`.shipkit/research/1-0-readiness.md`, line 109).

## Conflicts found
- **Non-goal "No removing a shipped free feature, and no caps on the user's own data"**
  (`.shipkit/product.md`, line 24). Truncating long messages and params at capture caps the user's
  data. The alternative that avoids it is clamping each value only to what its column can hold, which
  changes nothing outside MySQL. *Question 1: the user chose caps and reworded the non-goal.*
- **Paramount non-goal: nothing that slows the host app beyond its budget** (line 18). The wider
  message redaction runs regexes on the capture path. They must stay linear on untrusted text, and
  the message cap (if chosen) bounds their input.
- **Open specs:** none cover this. `functional-fixes-0-17` (merged) touched `log_error.rb` and
  `find_or_increment_error.rb`, not the filter or the columns.
- **Decisions:** `.shipkit/decisions/0001` is not touched.

## Answers
1. Caps at capture, as decided on 2026-10-22, or only clamp to each column's capacity?
   **Caps, and clarify the non-goal** (user, 2026-10-22). The non-goal now rules out quotas on how
   many errors are kept or for how long. Per-field size limits that keep a capture storable and the
   host app within budget are allowed, consistent with the paramount rule that RED gives up its data
   first. `.shipkit/product.md` is updated in the same change.

## Assumptions made
- **Decided on 2026-10-22, not re-asked:**
  - filtering fails closed: a filter step that raises stores `[FILTERED]` for that field, never the
    raw value;
  - message redaction also covers `key: value`, `"key":"value"` pairs and `Bearer <token>`;
  - a URL whose query string can't be parsed is redacted pair by pair;
  - the docs say message redaction is best-effort;
  - with no `secret_key_base`, no session ID is stored.
- **Request params that aren't JSON** (a string from a caller) go through the message redaction rules
  instead of being stored verbatim or replaced wholesale. A parse failure is an input shape, not a
  filter failure.
- **No new settings.** Cap sizes, if caps are chosen, are constants with a stated reason (the 1.0
  config freeze).
- **Grouping is unchanged:** the fingerprint hashes the first 500 characters of the raw message
  before anything is truncated.
- **Public wording:** a bug fix ("errors with very long messages or params were lost on MySQL") and
  hardening ("secret filtering now fails closed"). No review IDs.

## Out of scope
- The live-updates and host-hygiene work for 0.17.0 (separate specs).
- Redacting arbitrary free text beyond the listed shapes. Redaction stays best-effort.
- Changing column types (MEDIUMTEXT on MySQL), which would need a migration in every host's deploy.
