# Tasks: Overhead benchmark

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `overhead-benchmark/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Never run the benchmark
and rspec at the same time on one machine: the numbers would be wrong, though the databases don't
collide.

- [x] **T1** The timing core: rounds, median, p95, budget verdict → REQ-4, REQ-7
  - Files: benchmark/timer.rb, spec/benchmark/timer_spec.rb
  - Test: timer_spec, with an injected clock:
    - known samples → the expected median, p95 and median of round medians;
    - a median over budget → FAIL;
    - one at budget → PASS;
    - a failing gated result makes the run's exit status 1;
    - a failing reported-only row doesn't
  - After: none
  - Done when: `R rspec spec/benchmark/timer_spec.rb` → 0 failures
- [x] **T2** The harness boots the dummy app like production, on a scratch database → REQ-1, REQ-5, REQ-6
  - Files: benchmark/harness.rb, benchmark/initializers/rails_error_dashboard.rb, bin/benchmark, spec/benchmark/harness_spec.rb, spec/benchmark/offline.rb
  - Test: harness_spec runs `bin/benchmark --list` in a subprocess and asserts:
    - eager loading on, reloading off;
    - the database file is under `tmp/`, not `spec/dummy/db/test.sqlite3`;
    - the job adapter enqueues nothing;
    - the environment block names Ruby, Rails, adapter, CPU model and count, OS and commit;
    - no network access is attempted (WebMock disallows all)
  - After: T1
  - Done when: `R rspec spec/benchmark/harness_spec.rb` → 0 failures
- [x] **T3** The measurements → REQ-2, REQ-3, REQ-4, REQ-6
  - Files: benchmark/scenarios.rb, benchmark/report.rb, benchmark/timer.rb, bin/benchmark, spec/benchmark/scenarios_spec.rb, spec/benchmark/report_spec.rb, spec/benchmark/timer_spec.rb
  - Test: scenarios_spec runs each scenario for a few iterations and asserts it exercised the
    real code path (spied). The gated scenarios are:
    - capture, with versus without RED (the enqueue happened, and the subscriber ran);
    - storm check, calm and active (the breaker state is checked);
    - breadcrumb (one crumb recorded);
    - health snapshot.

    The reported-only scenarios are sync capture, message filtering, params fitting and the
    reopen collision (`claim_conflicting_row` reached). report_spec: the Markdown table shows
    each row's median, p95, budget and verdict (REQ-4), under the environment block (REQ-6).
  - After: T2
  - Done when: `R rspec spec/benchmark/scenarios_spec.rb` → 0 failures, and `R bin/benchmark` prints a table with all ten rows (nine until T4's review added shedding)
- [x] **T4** CI runs it and fails on a breach → REQ-8, REQ-9
  - Files: .github/workflows/ci.yml, spec/ci/workflows_spec.rb
  - Test: workflows_spec:
    - a `benchmark` job exists with `permissions: contents: read` and SHA-pinned actions;
    - it runs on pushes to main;
    - on pull requests it runs when `changes` reports `capture`;
    - the `capture` output matches the capture-path globs and `bin/benchmark`;
    - the job passes `--summary "$GITHUB_STEP_SUMMARY"`
  - After: T3
  - Done when: `R rspec spec/ci/workflows_spec.rb` → 0 failures, and the PR's CI run shows the
    benchmark table in the job summary
- [ ] **T5** README and docs quote the CI numbers → REQ-10
  - Files: README.md, docs/FEATURES.md, docs/LLM_OBSERVABILITY.md, _features/, _getting_started/, spec/docs/benchmark_claims_spec.rb
  - Test: benchmark_claims_spec:
    - README no longer says no benchmark ships;
    - it links `bin/benchmark`;
    - every overhead figure it quotes names the runner it came from;
    - the same holds for the two docs pages and any Jekyll copy of that text
  - After: T4
  - Done when: `R rspec spec/docs/benchmark_claims_spec.rb` → 0 failures, with the figures taken
    from a green benchmark run on main
