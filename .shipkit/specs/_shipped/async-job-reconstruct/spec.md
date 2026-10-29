# Spec: Async job rebuilds exceptions without trusting the reported type

> Drafted 2026-10-22 as a security fix for 0.16.2; it was folded into 0.17.0 instead, with no
> 0.16.x patch release.
> Status: shipped in 0.17.0 (#306)

## Purpose

With `async_logging` on, `Commands::LogError.call_async` queues `class_name: exception.class.name`.
For a `ManualErrorReporter` report that name is the caller's `error_type`, which hosts take from
their own clients (the mobile guide passes `error[:error_type]` straight through).

`AsyncErrorLoggingJob#reconstruct_exception` resolves that name with `constantize`. When the
resolved constant does not descend from `Exception`, `allocate_exception` steps aside and
`construct_exception` calls `.new(message)` on it anyway. So a host app's client can choose which
loaded class the worker instantiates, with a message it also chooses (CWE-470).

- The sync path is unaffected: it passes the `SyntheticException` through and never resolves the
  name.
- Server-side exceptions are unaffected in practice: their class names come from real Ruby
  exception classes.
- Since v0.1.20 (2026-01-03), when `ManualErrorReporter` arrived, the job has resolved the name and
  called `.new(message)` on it.
- Since v0.16.0, client reports carry `_capture_source: "client"` across the queue. Jobs enqueued
  by older versions do not.

## Requirements (EARS)

- **REQ-1:** When the async job processes a payload whose context marks it as a client report
  (`_capture_source == "client"`), the job shall rebuild it as a
  `ManualErrorReporter::SyntheticException` carrying the reported type, message and backtrace, and
  shall not resolve the reported type to a Ruby constant.
- **REQ-2:** If the job resolves a class name and the result is not a `Class` that descends from
  `Exception`, then the job shall rebuild the exception as a `StandardError`, and shall neither
  allocate nor construct an instance of the resolved constant.
- **REQ-3:** When a client report is captured with `async_logging` on, the stored error log shall
  have the same `error_type`, `message`, `backtrace`, `error_hash` and `capture_source` as the
  same report captured with `async_logging` off.
- **REQ-4:** When the job processes a server-side exception whose class descends from
  `Exception`, the job shall keep rebuilding it as that class, including classes whose
  constructors take something other than a message (existing behaviour).
- **REQ-5:** While a payload lacks a capture-source marker (a job enqueued by a version before
  0.16.0), the job shall apply REQ-2.

## Out of scope

- Restricting which strings a host may pass as `error_type`. After this fix, the reported type is
  only a label, which is all it ever was on the sync path.
- The other `constantize` calls in `lib/` (`user_model`, `ignored_exceptions`): they read deployer
  configuration, not request data.
