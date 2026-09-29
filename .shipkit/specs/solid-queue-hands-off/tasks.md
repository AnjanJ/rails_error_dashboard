# Tasks: Keep RED's hands off Solid Queue (0.14.3)

Each task lands as one commit, with its tests written first and seen failing.

- [x] **T1** (`d5c3fbd`) Stop telling apps to run `solid_queue:install`: verify's fix line, the generator's
  three messages, the guide and its Jekyll mirror → REQ-1..5. Tests: `verify_task_spec.rb`,
  `solid_queue_generator_spec.rb`.
- [x] **T2** (`f3a5bbf`, the contract failed 11 of 32 on the old rules) Contract with the real Solid Queue: test-only `solid_queue` in the Gemfile (Rails 7.1+),
  `spec/fixtures/solid_queue/solid_queue_probe.rb`, `SolidQueueConfigCheck.processes_for`, and the
  three fixes it finds → REQ-6..9. Tests: `solid_queue_config_check_contract_spec.rb`, updated
  `solid_queue_config_check_spec.rb`.
- [x] **T3** (`2a72c90`, proven red with the v0.14.2 generator) Hands-off guard → REQ-10. Test: `generators_hands_off_spec.rb`. Scenario runner:
  checksum Solid Queue's files in `solid_queue_real`.
- [ ] **T4** Verification: full suite (5483/0 on Rails 8.1.4), chaos on every code commit (5/5,
  1496), scenarios `solid_queue_real` 33/0 (Solid Queue's files unchanged after install, re-install,
  the deprecated generator and uninstall), `fresh_sqlite_81` 38/0, `up_0_14_2` 41/0, `fresh_pg_81`
  32/0. Left: CI on the PR, including the Rails 7.1 rows.
