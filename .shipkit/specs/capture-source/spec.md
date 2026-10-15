# Spec: Capture source

> Spec accepted at commit `93ba34d` on spec/0-16-0.
> Status: open
> Paths: lib/rails_error_dashboard/manual_error_reporter.rb,lib/rails_error_dashboard/commands/,lib/rails_error_dashboard/services/,app/models/rails_error_dashboard/error_log.rb,app/helpers/rails_error_dashboard/backtrace_helper.rb,app/views/rails_error_dashboard/errors/,docs/SOURCE_CODE_INTEGRATION.md,db/migrate/,spec/

## Purpose
Record how each error was captured: by RED inside the app (server), or from a report a client sent
through `ManualErrorReporter`. RED then never reads source files for frames a client supplied. This
closes the residual of advisory GHSA-q7r3-w7p3-95h5: today an injected frame can still make the
source viewer show any Ruby file or view template under `app/`.

## User stories
- As a maintainer who forwards frontend or mobile errors to RED, I want those reports never to make
  the dashboard read files from my server, so that a client cannot choose what source code
  dashboard users and my LLM provider see.

## Requirements (EARS)
- **REQ-1.** When RED records an error through `ManualErrorReporter`, it shall record the capture
  source as client.
- **REQ-2.** When RED records an error any other way (the middleware, the `Rails.error`
  subscriber, background jobs, crash import, the dashboard's test error, `ErrorLog.log_error`), it
  shall record the capture source as server.
- **REQ-3.** RED shall group errors identically whatever their capture source: the source shall not
  be part of the fingerprint.
- **REQ-4.** If the backtrace an error page shows came from a client report, then View Source shall
  not read any file for its frames, and the page shall say the frames came from a client report.
- **REQ-5.** If the backtrace came from a client report, then Copy for LLM and the AI help context
  shall contain no source-code snippets.
- **REQ-6.** If the backtrace came from a client report, then RED shall not run `git blame` for its
  frames.
- **REQ-7.** While an error has no recorded capture source (recorded before 0.16.0), RED shall treat
  it as server-captured.
- **REQ-8.** If recording the capture source fails, then RED shall still record the error, and
  shall not raise in the host application.
- **REQ-9.** When a host upgrades from 0.15.x by running the installer and `db:migrate`, the capture
  source columns shall exist in the error database (same or separate database) on SQLite,
  PostgreSQL and MySQL.
- **REQ-10.** The source-code integration docs shall state that client reports never get View
  Source, Copy for LLM snippets or blame. [untested: prose, verified by reading]

## Out of scope
- The canonical event-envelope refactor.
- Classifying rows recorded before the upgrade from heuristics (`platform`,
  `request_url = "manual"`).
- Changing what `ManualErrorReporter` accepts, or validating client backtraces at capture.
- Showing the capture source as a filter or a column on the errors list.
