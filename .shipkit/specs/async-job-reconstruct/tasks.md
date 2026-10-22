# Tasks: Async job rebuilds exceptions without trusting the reported type

Every requirement gets a failing test first, citing `async-job-reconstruct/REQ-N`.

- [ ] **T1** (REQ-1, REQ-3) Failing specs in `spec/jobs/rails_error_dashboard/async_error_logging_job_spec.rb`:
  - a client-marked payload whose type resolves to a spec-defined class that records `new` calls:
    no `new` call, and the row keeps the reported type;
  - a client-marked payload naming a real exception class is rebuilt as a `SyntheticException`;
  - end to end: `ManualErrorReporter.report` with `async_logging` on, perform the enqueued job,
    and compare `error_type`, `message`, `backtrace`, `error_hash` and `capture_source` with the
    same report captured sync.
- [ ] **T2** (REQ-2, REQ-5) Failing specs: an unmarked payload whose name resolves to a non-exception
  class (and to a module) calls no constructor and is stored as reported.
- [ ] **T3** (REQ-4) Confirm the existing reconstruction examples (RecordInvalid, keyword-argument
  error, message from constructor state) still pass unchanged.
- [ ] **T4** Implement D1 and D2 in `AsyncErrorLoggingJob`. Prove red then green: revert each half
  and watch its own examples fail.
- [ ] **T5** Full suite (one rspec process), then chaos through the commit hook.
- [ ] **T6** (private, `tasks/`) Check the affected range against the shipped gems, the way the
  credential-guard advisory was checked, and draft the GHSA text and CVSS for the user.
- [ ] **T7** Release sitting, with the user: push, PR, CI, release PR with notes, merge, publish the
  advisory, CVE decision.
