# Tasks: Capture source

Tests cite `capture-source/REQ-N`. Build this spec after `occurrence-context-history`: both touch
`log_error.rb`, `spec/dummy/db/schema.rb` and the locale files. Write commit messages that state
the new behaviour without exploit detail (the residual of GHSA-q7r3-w7p3-95h5).

- [x] **T1** Capture-source columns → REQ-9
  - Files: db/migrate/20261015000002_add_capture_source_to_error_occurrences_and_error_logs.rb, spec/dummy/db/schema.rb, spec/migrations/add_capture_source_spec.rb
  - Test: spec/migrations/add_capture_source_spec.rb (both nullable columns exist after migrating; re-running is a no-op)
  - After: none
  - Done when: `bundle exec rspec spec/migrations/add_capture_source_spec.rb` → all pass, and `bin/check-schema-parity` → agrees
- [x] **T2** Record the marker on capture → REQ-1, REQ-2, REQ-3, REQ-7, REQ-8
  - Files: lib/rails_error_dashboard/manual_error_reporter.rb, lib/rails_error_dashboard/commands/log_error.rb, spec/commands/log_error_capture_source_spec.rb
  - Test: spec/commands/log_error_capture_source_spec.rb, covering:
    - a `ManualErrorReporter` report is client, sync and async
    - the caller's `source:` can't make it server
    - middleware, `Rails.error.report` and `ErrorLog.log_error` captures are server
    - a client report and a server capture of the same error share one group
    - a nil marker reads as server
    - a failing marker write still records the error
  - After: T1
  - Done when: `bundle exec rspec spec/commands/log_error_capture_source_spec.rb` → all pass
- [x] **T3** Keep `backtrace_source` in step with the shown backtrace → REQ-2, REQ-4
  - Files: lib/rails_error_dashboard/commands/find_or_increment_error.rb, lib/rails_error_dashboard/services/crash_capture.rb, lib/rails_error_dashboard/commands/flush_storm_counts.rb, lib/rails_error_dashboard/services/storm_protection/gate.rb, lib/rails_error_dashboard/services/storm_protection/count_buffer.rb, spec/commands/find_or_increment_error_capture_source_spec.rb
  - Test: spec/commands/find_or_increment_error_capture_source_spec.rb, covering:
    - when `backtrace_upgrade` replaces a one-line client backtrace with a server one, the row
      becomes server
    - when the stored backtrace is multi-line and from a client, a later server capture leaves it
      client
    - crash import is server; a storm exemplar takes the source of the counted event its frame came
      from (client for a ManualErrorReporter report), and an entry without one reads as server
  - After: T2
  - Done when: `bundle exec rspec spec/commands/find_or_increment_error_capture_source_spec.rb` → all pass
- [ ] **T4** Gate View Source, blame and the Markdown formatter → REQ-4, REQ-5, REQ-6
  - Files: app/models/rails_error_dashboard/error_log.rb, app/views/rails_error_dashboard/errors/_error_info.html.erb, lib/rails_error_dashboard/services/markdown_error_formatter.rb, config/locales/en.yml, config/locales/de.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml, spec/requests/errors_show_client_backtrace_spec.rb, spec/services/markdown_error_formatter_spec.rb
  - Test: spec/requests/errors_show_client_backtrace_spec.rb, covering:
    - a client report's page has no View Source toggle, reads no file, runs no blame, and shows
      the note
    - a server capture of the same file still gets View Source
    - Copy for LLM and the AI-help context hold no source snippet for the client report
  - After: T3
  - Done when: `bundle exec rspec spec/requests/errors_show_client_backtrace_spec.rb spec/services/markdown_error_formatter_spec.rb` → all pass, and `bin/i18n-check` → no failures
- [ ] **T5** Document client reports in the source integration docs → REQ-10
  - Files: docs/SOURCE_CODE_INTEGRATION.md, _features/source-code-integration.md
  - Test: none (REQ-10 is prose)
  - After: none
  - Done when: both pages state that client reports never get View Source, snippets or blame, and the full suite `bundle exec rspec` → 0 failures

## After the gate
- Run the end-to-end probe: a client report through `ManualErrorReporter` naming a real app file
  gets no View Source, no snippets and no blame, while a server capture of that file does.
- Run the focused release scenarios and `bin/pre-release-test all`.
