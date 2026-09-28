# Tasks: Setup hardening (0.14.3)

Test first for each: every new example fails on the v0.14.2 code for the requirement's reason, then
passes.

- [ ] **T1** Retire the Solid Queue generator. Add `Services::SolidQueueConfigCheck` and the
  verify line, and update the Quick Start docs → REQ-1..6. Tests: `solid_queue_config_check_spec.rb`,
  `solid_queue_generator_spec.rb` (rewritten), verify spec. One-off evidence: the old template vs
  Solid Queue's template through real `SolidQueue::Configuration` (0 vs 1 dispatchers).
- [ ] **T2** `Queries::UninstallPlan` and `Commands::DropAllTables`, used by the rake task and the
  uninstall generator (drop first) → REQ-7..12. Tests: `uninstall_plan_spec.rb` (discovery, FK
  order, the sort on a fake graph); `drop_all_tables_spec.rb` (seeded rows, drop inside a rolled-back
  transaction, schema cache cleared); rake and generator specs. Chaos: an uninstall step in
  full_sync and full_separate_db.
- [ ] **T2b** Reproduce `cleanup_resolved` on SQLite with dependent rows. If it's real, fix it with
  batched dependent-first deletion → REQ-20.
- [ ] **T3** `LOG_LEVELS` gains `:fatal`, the logger never raises, and `validate!` derives its list
  → REQ-13..15. Test: `logger_spec.rb`.
- [ ] **T4** Blank-credential warning in development, plus the verify message → REQ-16, REQ-17.
  Tests: configuration spec, verify spec.
- [ ] **T5** Truthful installer text → REQ-18, REQ-19. Test: install_generator_spec.
- [ ] **T6** Verification: the full suite on Rails 8.1, the drop spec on PostgreSQL, chaos
  `release_audit`, and CI on the PR.
