# Tasks: Migrations that roll back what they add (issue #326)

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `migration-rollback/REQ-N`. One commit per task, test and code together. Commits and the PR
body say "Refs #326", never "Closes".

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Run one rspec process at a
time. The round-trip spec builds its own scratch databases and never touches
`spec/dummy/db/test.sqlite3`.

- [ ] **T1** The round-trip harness, proven on one migration → REQ-1, REQ-4, REQ-6
  - Files: spec/support/migration_round_trip.rb, spec/db/migrations/round_trip_spec.rb, db/migrate/20261010000001_create_missing_translations.rb
  - Test: round_trip_spec, for `create_missing_translations` on both histories:
    - **upgrade:** every migration up to it, complete schema skipped;
    - **fresh:** the complete schema plus every migration up to it.

    In each: down → table gone; up → table back. It fails today, because down leaves the table.
    Also record the per-case runtime in `design.md`.
  - After: none
  - Done when: `R rspec spec/db/migrations/round_trip_spec.rb` → 0 failures
- [ ] **T2** The other ten migrations that own their object → REQ-1, REQ-2, REQ-3
  - Files: db/migrate/20260307000001_create_rails_error_dashboard_diagnostic_dumps.rb, db/migrate/20260613000001_create_storm_events.rb, db/migrate/20260730000001_create_rails_error_dashboard_rack_attack_events.rb, db/migrate/20260824000001_add_user_agent_to_rack_attack_events.rb, db/migrate/20260826000001_add_environment_to_error_logs.rb, db/migrate/20260915000004_create_storm_flush_batches.rb, db/migrate/20260919000001_create_event_counts.rb, db/migrate/20260920000001_add_buckets_incomplete_to_storm_events.rb, db/migrate/20260920000002_create_event_timing_gaps.rb, db/migrate/20261015000001_create_rails_error_dashboard_error_occurrence_contexts.rb, spec/db/migrations/round_trip_spec.rb
  - Test: round_trip_spec covers all eleven own-object migrations on both histories:
    - down → object gone;
    - down again → no error, no change (REQ-2);
    - up, then up again → object present, no error (REQ-3)
  - After: T1
  - Done when: `R rspec spec/db/migrations/round_trip_spec.rb` → 0 failures
- [ ] **T3** The fifteen migrations the complete schema shadows → REQ-1, REQ-2, REQ-3, REQ-5
  - Files: db/migrate/20251224000001_create_rails_error_dashboard_error_logs.rb, db/migrate/20251224081522_add_better_tracking_to_error_logs.rb, db/migrate/20251224101217_add_controller_action_to_error_logs.rb, db/migrate/20251225071314_add_optimized_indexes_to_error_logs.rb, db/migrate/20251225085859_add_enhanced_metrics_to_error_logs.rb, db/migrate/20251225093603_add_similarity_tracking_to_error_logs.rb, db/migrate/20251225100236_create_error_occurrences.rb, db/migrate/20251225101920_create_cascade_patterns.rb, db/migrate/20251225102500_create_error_baselines.rb, db/migrate/20251226020000_add_workflow_fields_to_error_logs.rb, db/migrate/20251226020100_create_error_comments.rb, db/migrate/20251229111223_add_additional_performance_indexes.rb, db/migrate/20260106094220_create_rails_error_dashboard_applications.rb, db/migrate/20260306000003_create_rails_error_dashboard_swallowed_exceptions.rb, db/migrate/20260323000001_add_muted_to_error_logs.rb, spec/db/migrations/round_trip_spec.rb
  - Test: round_trip_spec covers the fifteen:
    - on the upgrade history: down → object gone;
    - on the fresh history: down → either gone, or failed with the database's foreign-key error
      and the version still in `schema_migrations` (REQ-1 as refined), never "reverted" with the
      object present;
    - up and up again as in T2;
    - the complete-schema `down` still drops exactly its seven tables (REQ-5)
  - After: T2
  - Done when: `R rspec spec/db/migrations/round_trip_spec.rb` → 0 failures, and the same file is
    green on the PostgreSQL and MySQL `adapter-test` rows of the PR's CI run
- [ ] **T4** No migration returns early from `change` on an existence check → REQ-7
  - Files: spec/db/migrations/no_guarded_change_spec.rb
  - Test: no_guarded_change_spec parses every `db/migrate/*.rb` with Prism and fails on a `change`
    whose body returns early on a `*_exists?` check. Its own example also runs the check on the
    pre-fix text of one migration and expects a failure.
  - After: T3
  - Done when: `R rspec spec/db/migrations/no_guarded_change_spec.rb` → 0 failures
- [ ] **T5** The rollback docs say what rolls back → REQ-8
  - Files: docs/TROUBLESHOOTING.md, docs/GLOSSARY.md, _reference/troubleshooting.md, _reference/glossary.md, spec/docs/rollback_docs_spec.rb
  - Test: rollback_docs_spec, for each of the four pages:
    - it names the four irreversible migrations and `20260915000001` as where `db:rollback` stops;
    - it says installs from before 0.18.0 keep their old copies;
    - it shows how to remove a leftover table or column;
    - GLOSSARY no longer claims rollbacks are simply supported
  - After: none
  - Done when: `R rspec spec/docs/rollback_docs_spec.rb` → 0 failures
