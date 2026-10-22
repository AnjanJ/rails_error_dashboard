# Tasks: Capture hardening for 0.17.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `capture-hardening-0-17/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. The shell exports a stale
`RAILS_VERSION` that re-pins the lockfile. Run one rspec process at a time.

- [ ] **T1** Limits for a message and for request params → REQ-1, REQ-2
  - Files: lib/rails_error_dashboard/services/capture_limits.rb, spec/services/capture_limits_spec.rb
  - Test: capture_limits_spec:
    - a 70,000-character message → the first 10,000 characters plus a marker naming the 60,000 cut;
    - a message at or under the limit is returned unchanged;
    - 70 KB params with one huge value → valid JSON of at most 64,000 bytes, the small keys kept, `_truncated: true`;
    - non-JSON params → cut at a UTF-8 boundary with a marker;
    - nothing raises on nil or odd input
  - After: none
  - Done when: `R rspec spec/services/capture_limits_spec.rb` → 0 failures
- [ ] **T2** A per-column net for text values → REQ-3
  - Files: app/models/rails_error_dashboard/error_logs_record.rb, spec/models/error_logs_record_clamp_spec.rb
  - Test: error_logs_record_clamp_spec:
    - a 70 KB `backtrace` → at most 65,535 bytes, valid UTF-8, with a marker;
    - a 70 KB `local_variables` (JSON) → nil;
    - values under the limit and non-text columns are untouched;
    - the occurrence-context model gets the same treatment
  - After: none
  - Done when: `R rspec spec/models/error_logs_record_clamp_spec.rb` → 0 failures
- [ ] **T3** Apply the limits on every capture route → REQ-1, REQ-2, REQ-3, REQ-4, REQ-5
  - Files: lib/rails_error_dashboard/commands/log_error.rb, lib/rails_error_dashboard/services/storm_protection/gate.rb, lib/rails_error_dashboard/commands/flush_storm_counts.rb, spec/commands/log_error_capture_limits_spec.rb
  - Test: log_error_capture_limits_spec:
    - a 70,000-character message, sync and async → one row, message cut with the marker, `error_hash` equal to the full message's;
    - 70 KB params → one row, valid JSON with `_truncated`;
    - oversized locals → one row, `local_variables` nil;
    - a storm-counted 70,000-character message → the row's message is cut.

    Runs on CI's MySQL row as well (REQ-4).
  - After: T1, T2
  - Done when: `R rspec spec/commands/log_error_capture_limits_spec.rb spec/commands/log_error_queue_redaction_spec.rb spec/commands/flush_storm_counts_spec.rb spec/services/storm_protection/gate_spec.rb` → 0 failures
- [ ] **T4** Filtering fails closed; text that isn't JSON gets the message rules → REQ-6, REQ-7, REQ-11
  - Files: lib/rails_error_dashboard/services/sensitive_data_filter.rb, spec/services/sensitive_data_filter_spec.rb
  - Test: sensitive_data_filter_spec:
    - a helper that raises → that field `[FILTERED]`;
    - a nil parameter filter → message, params, URL and cause chain each `[FILTERED]`;
    - a raise in `filter_attributes` → the four fields `[FILTERED]`, not the raw attributes (this replaces "returns original attributes if filtering raises unexpectedly");
    - non-JSON params `{"password":"x","a"` → the secret redacted
  - After: none
  - Done when: `R rspec spec/services/sensitive_data_filter_spec.rb` → 0 failures
- [ ] **T5** Redact `key: value`, JSON pairs, Bearer tokens and unparseable URLs, in linear time → REQ-8, REQ-9, REQ-10, REQ-12
  - Files: lib/rails_error_dashboard/services/sensitive_data_filter.rb, spec/services/sensitive_data_filter_spec.rb
  - Test: sensitive_data_filter_spec:
    - `password: x`, `password: "a b"`, `{"token":"x"}`, `"pin": 1234` and `Bearer x.y.z` → redacted, with non-sensitive keys kept;
    - `/login?password=x&q=100%` → the password redacted, `q` kept;
    - a 10,000-character adversarial message for each pattern → under 50 ms
  - After: T4
  - Done when: `R rspec spec/services/sensitive_data_filter_spec.rb spec/services/breadcrumb_collector_spec.rb spec/services/variable_serializer_spec.rb` → 0 failures
- [ ] **T6** Crash imports are filtered and limited → REQ-15
  - Files: lib/rails_error_dashboard/services/crash_capture.rb, spec/services/crash_capture_spec.rb
  - Test: crash_capture_spec "import filters and limits what it stores": a crash file whose message holds `password=x` and 20,000 characters → the row has `[FILTERED]` and a cut message
  - After: T1, T2
  - Done when: `R rspec spec/services/crash_capture_spec.rb spec/services/crash_capture_boot_spec.rb` → 0 failures
- [ ] **T7** No secret, no session ID → REQ-14
  - Files: lib/rails_error_dashboard/services/sensitive_data_filter.rb, spec/commands/log_error_session_digest_spec.rb
  - Test: log_error_session_digest_spec "stores no session ID when the app has no secret_key_base"
  - After: T5
  - Done when: `R rspec spec/commands/log_error_session_digest_spec.rb spec/services/sensitive_data_filter_spec.rb` → 0 failures
- [ ] **T8** Docs: best-effort redaction, fail closed, the limits → REQ-13
  - Files: README.md, docs/FEATURES.md, docs/guides/CONFIGURATION.md, _features/, _guides/, _reference/, _getting_started/
  - Test: none (REQ-13 is prose, checked by reading)
  - After: none
  - Done when: `grep -rn "best-effort" README.md docs/FEATURES.md docs/guides/CONFIGURATION.md _features _guides` shows the note in each file and its site copy

## After the gate
- Full suite, RuboCop on tracked files, and `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test all` (read FINAL RESULTS).
- Runtime proofs:
  - the redaction probe in the separate-database lab app: no LEAKED lines;
  - the MySQL size probe on a fresh MySQL database: every case stored.
- One PR with `BEGIN_COMMIT_OVERRIDE`, public wording only. Merge only with the user's OK.
- The 0.17.0 release notes carry the two lines from `design.md`.
