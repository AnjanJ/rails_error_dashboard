# Design: Async job rebuilds exceptions without trusting the reported type

## D1. What the job rebuilds for a client report

**Context.** The job needs an exception-shaped object to hand to `LogError.new(..., worker: true)`.
For a client report, the reported type names no Ruby class in the normal case ("TypeError" from
JavaScript, "NSException" from iOS), so the job already falls back to `StandardError` and carries
the reported type separately in `_reported_error_type`. The danger is the case where the name does
resolve.

**Alternatives.**
- (A) Keep resolving the name, and guard it: only a `Class` below `Exception` may be allocated.
- (B) Never resolve it: rebuild a `StandardError` and rely on `_reported_error_type` for the label.
- (C) Never resolve it: rebuild the same `ManualErrorReporter::SyntheticException` the sync path
  passes to `LogError`.

**Case for C.**
- The worker sees exactly the object the sync path sees, so REQ-3's parity holds by construction:
  `exception.class.name`, `is_a?` and the absent cause chain all behave as they do when sync.
- The reported type never reaches `constantize`, so a constant lookup (and any autoload it would
  trigger) cannot be driven by a client at all.
- It is what the code already does on the request thread, so nothing new is invented.

**Case against C (my own choice).**
- A client report that names a real Ruby exception ("ArgumentError") used to be rebuilt as that
  class in the worker. Any host code that inspects the exception object in a worker-side hook
  (a plugin, a notification callback) would now see a `SyntheticException`. It already sees one on
  the sync path, so this removes a difference rather than adding one.
- It relies on the `_capture_source` marker, which payloads enqueued before 0.16.0 lack. D2 covers
  them.

**Decision:** C. I would reverse this if a host reports that a worker-side hook depended on a
client report being rebuilt as a real exception class, and that dependency cannot be met by
reading `error_type`.

## D2. Payloads that are not marked as client reports

**Context.** Server-side exceptions need their real class (REQ-4). Payloads enqueued by a version
before 0.16.0 carry no capture-source marker, so a client report from one of them looks like a
server payload.

**Alternatives.**
- (A) Resolve the name, and treat anything that is not a `Class` below `Exception` as
  `StandardError` before any constructor runs.
- (B) Resolve only names on an allowlist of known exception classes.
- (C) Leave the server path as it is.

**Case for A.**
- It is a type check on a value the job already computes, so it adds no lookups.
- It closes REQ-5's window for old in-flight jobs, and keeps a defence if a future capture path
  forgets the marker.
- `construct_exception` then only ever runs on an `Exception` subclass, which is the case its
  comment was written for.

**Case against A (my own choice).**
- It still calls `constantize` on the queued name, so for an unmarked payload a lookup can still
  autoload a constant. In production the app is eager-loaded, so the lookup finds only what is
  already loaded, and nothing is instantiated unless it is an `Exception`.
- (B) would be tighter, but no allowlist can name every host's own exception classes.

**Decision:** A. I would reverse this if a reachable path is found that queues an unmarked payload
built from request data in 0.16.2 or later; that path should then set the marker, or the server
path should move to (B).
