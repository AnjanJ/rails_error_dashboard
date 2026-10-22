# Tasks: Functional fixes for 0.17.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `functional-fixes-0-17/REQ-N`. One `fix:` commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. The shell exports a stale
`RAILS_VERSION` that re-pins the lockfile. Run one rspec process at a time.

- [x] **T1** Import boot crashes into the separate error database → REQ-1
  - Files: lib/rails_error_dashboard/engine.rb, test/pre_release/templates/full_separate_db_initializer.rb, bin/pre-release-test, test/pre_release/chaos/phase_o_boot_errors.rb
  - Test: chaos phase O in the `full_separate_db` app. The app gets crash capture and the injected Zeitwerk boot crash. Phase O's new O3 check: the row is on `ErrorLogsRecord`'s database, and the primary database has no RED table. It fails on unfixed code, because there is no boot_crash row and the file is left `.failed`
  - After: none
  - Done when: `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test full_separate_db` → FINAL RESULTS all passed, with phase O in the list
- [x] **T2** Give async captures the same custom fingerprint as sync and storm captures → REQ-2
  - Files: lib/rails_error_dashboard/commands/log_error.rb, spec/commands/log_error_queue_redaction_spec.rb
  - Test: log_error_queue_redaction_spec "grouping parity across all three paths":
    - "lands a custom-fingerprinted error on one row from sync, async and storm", with `error_hash == SHA256(key)[0..15]`;
    - "completes an unmarked queued identity with the application id, as before" (jobs queued before the upgrade)
  - After: none
  - Done when: `R rspec spec/commands/log_error_queue_redaction_spec.rb spec/commands/log_error_spec.rb spec/services/error_hash_generator_spec.rb spec/integration/custom_fingerprint_context_spec.rb` → 0 failures
- [x] **T3** Record a recurrence whose reopen collides on the group identity → REQ-3
  - Files: lib/rails_error_dashboard/commands/find_or_increment_error.rb, spec/commands/find_or_increment_error_spec.rb
  - Test: find_or_increment_error_spec "when reopening a resolved row would collide with an unresolved row of the same identity":
    - two resolved rows from before group_window, three recurrences, each one counted on the unresolved row, and nothing raises;
    - the same through `LogError` with the environment stamped
  - After: none
  - Done when: `R rspec spec/commands/find_or_increment_error_spec.rb` → 0 failures on SQLite, and the same file on a fresh PostgreSQL database (`DATABASE_URL=postgres://localhost/<db> RED_TEST_SCHEMA=migrations`) → 0 failures
- [x] **T4** Reject stale or undated Linear deliveries → REQ-4, REQ-5, REQ-6
  - Files: app/controllers/rails_error_dashboard/webhooks_controller.rb, spec/requests/linear_webhook_spec.rb, spec/requests/issue_webhook_identity_spec.rb, docs/API_REFERENCE.md, _reference/api-reference.md
  - Test: linear_webhook_spec:
    - a delivery 61 s old → 401 and the error unchanged;
    - 61 s in the future → 401;
    - no `webhookTimestamp` → 401;
    - a non-numeric one → 401;
    - one 30 s old → processed
  - After: none
  - Done when: `R rspec spec/requests/linear_webhook_spec.rb spec/requests/issue_webhook_identity_spec.rb spec/controllers/webhooks_controller_spec.rb` → 0 failures
- [x] **T5** Correct the error reporter's note on `Rails.error.handle` → REQ-7
  - Files: lib/rails_error_dashboard/error_reporter.rb
  - Test: none (REQ-7 is a code comment, checked by reading)
  - After: none
  - Done when: the header says `handle` blocks are recorded only at a severity other than `:warning`, matching `#report`'s first line

## After the gate
- Full suite on SQLite: 6012 + new examples, 0 failures. Then RuboCop, and
  `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test all` (read FINAL RESULTS).
- One PR with public wording only. Use `Refs`, never `Closes`. Merge only with the user's OK.
- The 0.17.0 release notes carry the custom-fingerprint upgrade line from `design.md`.
