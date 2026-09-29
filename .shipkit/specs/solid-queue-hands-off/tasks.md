# Tasks: Keep RED's hands off Solid Queue (0.14.3)

Each task lands as one commit, with its tests written first and seen failing.

- [ ] **T1** Stop telling apps to run `solid_queue:install`: verify's fix line, the generator's
  three messages, the guide and its Jekyll mirror → REQ-1..5. Tests: `verify_task_spec.rb`,
  `solid_queue_generator_spec.rb`.
- [ ] **T2** Contract with the real Solid Queue: test-only `solid_queue` in the Gemfile (Rails 7.1+),
  `spec/fixtures/solid_queue/solid_queue_probe.rb`, `SolidQueueConfigCheck.processes_for`, and the
  three fixes it finds → REQ-6..9. Tests: `solid_queue_config_check_contract_spec.rb`, updated
  `solid_queue_config_check_spec.rb`.
- [ ] **T3** Hands-off guard → REQ-10. Test: `generators_hands_off_spec.rb`. Scenario runner:
  checksum Solid Queue's files in `solid_queue_real`.
- [ ] **T4** Verification: full suite, chaos, `solid_queue_real` and `fresh_sqlite_81` scenarios, CI
  on the PR.
