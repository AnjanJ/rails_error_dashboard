# Spec: Functional fixes for 0.17.0

> Spec accepted at commit `5e3c16c` on fix/functional-fixes-0-17 (2026-10-22).
> Status: open
> Paths: lib/rails_error_dashboard/engine.rb,lib/rails_error_dashboard/commands/log_error.rb,lib/rails_error_dashboard/commands/find_or_increment_error.rb,app/controllers/rails_error_dashboard/webhooks_controller.rb,lib/rails_error_dashboard/error_reporter.rb,bin/pre-release-test,test/pre_release/,docs/API_REFERENCE.md,_reference/api-reference.md

## Purpose
Fix four verified functional bugs before 0.17.0, the release before 1.0.0.rc1. Two of them lose
captures silently: a boot crash in an app with a separate error database, and every recurrence of an
error whose resolved history predates 0.12.0. One splits a group by capture path. One rejects nothing
it should. Each was reproduced before this spec was written (see `intake.md`).

## User stories
- As a developer whose app keeps errors in a separate database, I want a crash during boot to appear
  on the dashboard after the next boot, so that I can see why the deploy failed.
- As a developer using `custom_fingerprint`, I want one error to stay one group whichever way it was
  captured, so that counts and notifications aren't split.
- As a developer upgrading from before 0.12.0, I want every recurrence of an old resolved error
  recorded, so that a regression is never silently invisible.
- As a developer receiving Linear webhooks, I want stale deliveries rejected, as Linear's docs
  recommend.

## Requirements (EARS)

### Boot-crash import with a separate error database
- **REQ-1.** Where `use_separate_database` is on, when the app boots with a crash file from an earlier
  process waiting, RED shall import that crash into the error database.

### One fingerprint per error, whichever path captured it
- **REQ-2.** Where `custom_fingerprint` returns a key for an error, a synchronous capture, an
  asynchronous capture and a storm-counted capture of that error shall store the same `error_hash`
  and count on one error row.

### Reopening a resolved error
- **REQ-3.** If reopening a resolved error would give it the same group identity as an unresolved
  error (application, `error_hash`, environment and window bucket), then RED shall record the
  occurrence on that unresolved error instead of dropping the capture.

### Linear webhook freshness
- **REQ-4.** When a Linear delivery passes the signature check and its `webhookTimestamp` is more than
  60 seconds away from the server's current time, the webhook endpoint shall respond 401 and change no
  error.
- **REQ-5.** If a Linear delivery passes the signature check but has no numeric `webhookTimestamp`,
  then the webhook endpoint shall respond 401 and change no error.
- **REQ-6.** When a Linear delivery passes the signature check and its `webhookTimestamp` is within
  60 seconds of the server's current time, the webhook endpoint shall process it as before.

### Error reporter documentation
- **REQ-7.** The header comment of `lib/rails_error_dashboard/error_reporter.rb` shall say that errors
  handled with `Rails.error.handle` are recorded only when reported at a severity other than
  `:warning`. [untested: a code comment, checked by reading]

## Out of scope
- **The 24-hour grouping window.** A reopened error keeps its original `occurred_at`, so the next
  occurrence after a reopen opens a new group. That is documented behaviour
  (`docs/TROUBLESHOOTING.md`, the grouping rules), not part of this fix.
- **Backfilling `group_window` on resolved history.** REQ-3 handles the collision at capture time
  instead (see `design.md`).
- **The swallowed-exception tracker's at-exit flush.** Its window is accepted, not fixed (see
  `design.md`).
- Timestamp checks for the GitHub, GitLab and Codeberg webhook handlers.
- The capture-hardening, live-updates and host-hygiene work for 0.17.0 (separate specs).
