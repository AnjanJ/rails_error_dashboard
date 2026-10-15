# Tasks: Per-occurrence context history

Tests cite `occurrence-context-history/REQ-N`. Build this spec before `capture-source`: both add a
migration and touch `log_error.rb` and `spec/dummy/db/schema.rb`.

- [x] **T1** Context table, model and associations → REQ-12, REQ-5
  - Files: db/migrate/20261015000001_create_rails_error_dashboard_error_occurrence_contexts.rb, spec/dummy/db/schema.rb, app/models/rails_error_dashboard/error_occurrence_context.rb, app/models/rails_error_dashboard/error_log.rb, app/models/rails_error_dashboard/error_occurrence.rb, lib/rails_error_dashboard.rb, spec/models/rails_error_dashboard/error_occurrence_context_spec.rb, spec/migrations/create_error_occurrence_contexts_spec.rb
  - Test: spec/migrations/create_error_occurrence_contexts_spec.rb (table and columns exist after migrating; the model lives in the error DB; destroying an error deletes its contexts)
  - After: none
  - Done when: `bundle exec rspec spec/migrations/create_error_occurrence_contexts_spec.rb spec/models/rails_error_dashboard/error_occurrence_context_spec.rb` → all pass, and `bin/check-schema-parity` → agrees
- [x] **T2** `occurrence_context_limit` option → REQ-3, REQ-4
  - Files: lib/rails_error_dashboard/configuration.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb
  - Test: spec/lib/rails_error_dashboard/configuration_validation_spec.rb (default 25; `validate!` rejects negative or non-Integer values)
  - After: none
  - Done when: `bundle exec rspec spec/lib/rails_error_dashboard/configuration_validation_spec.rb` → all pass
- [x] **T3** Record and trim contexts on capture → REQ-1, REQ-2, REQ-3, REQ-4, REQ-10, REQ-11
  - Files: lib/rails_error_dashboard/commands/record_occurrence_context.rb, lib/rails_error_dashboard/commands/log_error.rb, lib/rails_error_dashboard.rb, spec/commands/record_occurrence_context_spec.rb, spec/commands/log_error_occurrence_context_spec.rb
  - Test: spec/commands/log_error_occurrence_context_spec.rb, covering:
    - sync and async captures store the four values the error row got
    - `:lite` or empty captures store nothing
    - the 26th capture trims to 25
    - a limit of 0 stores nothing
    - a raising insert still records the error
  - After: T1, T2
  - Done when: `bundle exec rspec spec/commands/log_error_occurrence_context_spec.rb spec/commands/record_occurrence_context_spec.rb` → all pass
- [x] **T4** Delete contexts on every cleanup path → REQ-5
  - Files: app/jobs/rails_error_dashboard/retention_cleanup_job.rb, spec/jobs/retention_cleanup_occurrence_contexts_spec.rb
  - Test: spec/jobs/retention_cleanup_occurrence_contexts_spec.rb (retention, `cleanup_resolved` and batch delete leave no context rows for the deleted errors)
  - After: T3
  - Done when: `bundle exec rspec spec/jobs/retention_cleanup_occurrence_contexts_spec.rb` → all pass
- [x] **T5** Per-occurrence view with banner → REQ-6, REQ-7, REQ-9
  - Files: app/controllers/rails_error_dashboard/errors_controller.rb, lib/rails_error_dashboard/value_objects/occurrence_snapshot.rb, lib/rails_error_dashboard.rb, app/views/rails_error_dashboard/errors/show.html.erb, app/views/rails_error_dashboard/errors/_occurrence_banner.html.erb, config/locales/en.yml, config/locales/de.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml, spec/requests/errors_show_occurrence_spec.rb
  - Test: spec/requests/errors_show_occurrence_spec.rb, covering:
    - `?occurrence=` shows that occurrence's breadcrumbs and variables, with the banner
    - no param shows the latest snapshot
    - a foreign or missing id shows the latest snapshot and never the other error's
  - After: T4
  - Done when: `bundle exec rspec spec/requests/errors_show_occurrence_spec.rb` → all pass, and `bin/i18n-check` → no failures
- [x] **T6** "Captured occurrences" card in the History tab → REQ-8
  - Files: app/views/rails_error_dashboard/errors/show.html.erb, app/views/rails_error_dashboard/errors/_captured_occurrences.html.erb, app/controllers/rails_error_dashboard/errors_controller.rb, config/locales/en.yml, config/locales/de.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml, spec/requests/errors_show_occurrence_spec.rb
  - Test: spec/requests/errors_show_occurrence_spec.rb (the card links each occurrence that has context to `?occurrence=ID`; occurrences without context are not linked; the list query never selects payload columns)
  - After: T5
  - Done when: `bundle exec rspec spec/requests/errors_show_occurrence_spec.rb` → all pass, and `bin/i18n-check` → no failures
- [ ] **T7** Settings row, initializer template and docs → REQ-13
  - Files: app/views/rails_error_dashboard/errors/settings.html.erb, lib/generators/rails_error_dashboard/install/templates/initializer.rb, config/locales/en.yml, config/locales/de.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml, docs/guides/CONFIGURATION.md, _guides/configuration.md, docs/FEATURES.md, _getting_started/features.md
  - Test: none (REQ-13 is prose). `bin/i18n-check` guards the locale keys.
  - After: T6
  - Done when: `bin/i18n-check` → no failures, and the full suite `bundle exec rspec` → 0 failures

## After the gate
- Run the focused release scenarios with `RED_TABLES=15`: fresh install, upgrade from 0.15.0 on
  SQLite/PG/MySQL, a separate DB, and the multi-app join.
- Run `bin/pre-release-test all`. Look at `?occurrence=` manually in the dummy app.
