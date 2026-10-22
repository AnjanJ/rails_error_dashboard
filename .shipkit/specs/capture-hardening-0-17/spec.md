# Spec: Capture hardening for 0.17.0

> Spec accepted at commit `ecd8cd4` on fix/capture-hardening-0-17 (2026-10-22).
> Status: open
> Paths: lib/rails_error_dashboard/services/sensitive_data_filter.rb,lib/rails_error_dashboard/services/capture_limits.rb,lib/rails_error_dashboard/commands/log_error.rb,lib/rails_error_dashboard/commands/flush_storm_counts.rb,lib/rails_error_dashboard/services/storm_protection/gate.rb,app/models/rails_error_dashboard/error_logs_record.rb,README.md,docs/FEATURES.md,docs/guides/CONFIGURATION.md,_guides/,_features/,_reference/,_getting_started/,lib/rails_error_dashboard/services/crash_capture.rb,spec/services/sensitive_data_filter_spec.rb,spec/services/capture_limits_spec.rb,spec/commands/log_error_capture_limits_spec.rb,spec/models/error_logs_record_clamp_spec.rb,spec/services/crash_capture_spec.rb,spec/commands/log_error_session_digest_spec.rb

## Purpose
Make what a capture stores safe to store, on every adapter.
- Errors with very long messages or request params are silently lost on MySQL today, and stored
  unbounded elsewhere.
- Secret filtering stores the raw value whenever a filter step fails, and it recognises only
  `key=value` in free text.
- The session-ID digest falls back to a fixed key when the app has no `secret_key_base`.

## User stories
- As a developer on MySQL, I want an error with a huge message or a large POST body recorded, so that
  it doesn't vanish from the dashboard.
- As a developer, I want secrets kept out of what RED stores even when a filter step fails, so that
  they don't reach issues, notifications or AI help.
- As a developer, I want RED to tell me plainly that free-text redaction is best-effort.

## Requirements (EARS)

### Long values are stored, within limits
- **REQ-1.** When a captured error's message is longer than 10,000 characters, RED shall store the
  first 10,000 characters followed by a marker that says how many characters were cut.
- **REQ-2.** When a capture's request params are larger than 64,000 bytes, RED shall store them as
  valid JSON of at most 64,000 bytes, dropping the largest values first and adding
  `"_truncated": true`.
- **REQ-3.** RED shall write no text value larger than 65,535 bytes at capture. A longer plain-text
  value shall be shortened with a marker, and a longer structured (JSON) value shall be left out, and
  the error shall still be stored.
- **REQ-4.** An error whose message or request params exceed 64 KB shall be recorded on every
  supported adapter, MySQL in strict mode included.
- **REQ-5.** When a message is shortened, the error shall group exactly as it would with the full
  message.

### Secret filtering fails closed
- **REQ-6.** If filtering one field raises, then RED shall store `[FILTERED]` for that field.
- **REQ-7.** If RED can't build its parameter filter, then RED shall store `[FILTERED]` for every
  field it filters: the message, request params, request URL and cause chain.
- **REQ-8.** When a message contains `key: value` or a JSON pair (`"key": "value"` or
  `"key": value`) whose key the filter matches, RED shall store `[FILTERED]` in place of the value.
- **REQ-9.** When a message contains `Bearer <token>`, RED shall store `Bearer [FILTERED]`.
- **REQ-10.** If a request URL's query string can't be parsed, then RED shall store the URL with the
  value of each `key=value` pair whose key the filter matches replaced by `[FILTERED]`.
- **REQ-11.** When request params or a cause chain aren't valid JSON, RED shall redact them with the
  message rules (`key=value`, REQ-8 and REQ-9) instead of storing them as they came.
- **REQ-12.** The message filter shall take under 50 ms on any 10,000-character message.
- **REQ-13.** The README, the features guide and the configuration guide (and their site copies)
  shall say that message redaction is best-effort: it recognises the listed shapes, not every secret
  in free text. [untested: prose, checked by reading]

- **REQ-15.** When RED imports a crash from an earlier process, it shall filter and limit the stored
  values as it does for any other capture. (Added at design: the import wrote through
  `FindOrIncrementError` directly and never filtered.)

### Session digest
- **REQ-14.** If the app has no `secret_key_base`, then RED shall store no session ID, rather than
  one digested with a fixed key.

## Out of scope
- Redacting secrets in free text beyond the listed shapes.
- Changing column types (MEDIUMTEXT on MySQL); that would need a migration in every host's deploy.
- Making the limits configurable (the 1.0 config freeze).
- The live-updates and host-hygiene work for 0.17.0 (separate specs).
