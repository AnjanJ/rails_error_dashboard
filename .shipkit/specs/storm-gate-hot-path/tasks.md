# Tasks: Bring the storm check back under its budget

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `storm-gate-hot-path/REQ-N`. One commit per task, test and code together. This touches the
capture path, so the PR runs the full suite and chaos (`bin/with-ruby bin/pre-release-test all`,
reading the summary, not the exit code).

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Run one rspec process at a
time.

- [x] **T1** The buffer counts a known key in place, and takes its exemplar lazily → REQ-4
  - Files: lib/rails_error_dashboard/services/storm_protection/count_buffer.rb, spec/services/storm_protection/count_buffer_hot_path_spec.rb
  - Test: count_buffer_hot_path_spec:
    - recording a known key calls neither `Time.current` nor the exemplar block, and bumps the
      count, last seen and the current bucket;
    - a new key calls the block exactly once;
    - a full map counts the overflow without calling the block;
    - `snapshot!` output for a sequence of records is identical to what the 0.17.0 `record(key,
      parts)` path produces for the same sequence, including the time strings in a non-UTC
      `Time.zone`
  - After: none
  - Done when: `R rspec spec/services/storm_protection/` → 0 failures
- [ ] **T2** The gate builds the key per event and the exemplar only for a new entry → REQ-1, REQ-2, REQ-3, REQ-5
  - Files: lib/rails_error_dashboard/services/storm_protection/gate.rb, spec/services/storm_protection/gate_hot_path_spec.rb
  - Test: gate_hot_path_spec. Over a table of inputs: invalid bytes in the message and the
    environment, a custom fingerprint lambda, controller and action names, a client capture, and a
    message over 500 characters.
    - `gate_key_for(gate_identity(e, ctx))` equals `gate_key(gate_parts(e, ctx))` (REQ-3);
    - the entry buffered by the new path equals the one built from `gate_parts` (REQ-2);
    - on the calm path `redact` is never called, and in count-only mode it's called once per new
      fingerprint, not per event (REQ-1);
    - the custom fingerprint lambda runs once per event;
    - a raising identity step makes `admit!` return `:full` (REQ-5).

    The existing gate and drain specs stay green.
  - After: T1
  - Done when: `R rspec spec/services/storm_protection/` → 0 failures
- [ ] **T3** The storm rows pass on the machine of record → REQ-6
  - Files: .shipkit/specs/storm-gate-hot-path/intake.md
  - Test: `bin/benchmark` on the maintainer's M3 Max: both storm rows PASS. The before and after
    numbers are recorded in `intake.md`, and CI's numbers go in the PR once the benchmark's CI job
    exists.
  - After: T2
  - Done when: `R bin/benchmark` → both storm-check rows PASS, recorded in intake.md
