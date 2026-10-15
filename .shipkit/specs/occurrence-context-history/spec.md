# Spec: Per-occurrence context history

> Spec accepted at commit `93ba34d` on spec/0-16-0.
> Status: open
> Paths: lib/rails_error_dashboard/commands/,lib/rails_error_dashboard/configuration.rb,app/models/rails_error_dashboard/,app/controllers/rails_error_dashboard/errors_controller.rb,app/views/rails_error_dashboard/errors/,app/jobs/rails_error_dashboard/retention_cleanup_job.rb,db/migrate/,spec/

## Purpose
Keep the moment-of-failure context (breadcrumbs, system health, local and instance variables) for
the last N occurrences of an error, not only the latest one (C2), and let the error page show any
of them. This is ROADMAP C3: the long form of "the state of the process at the moment of failure".

## User stories
- As a developer debugging a recurring error, I want to open an earlier occurrence and see its
  breadcrumbs, system health and variables, so that I can tell what differed between failures.

## Requirements (EARS)
- **REQ-1.** When RED records an occurrence from a full-context capture, it shall store that
  occurrence's breadcrumbs, system health, local variables and instance variables as the
  occurrence's context.
- **REQ-2.** If an occurrence's capture has no context (a storm-protection `:lite` capture, or every
  piece empty), then RED shall store no context for it.
- **REQ-3.** RED shall keep at most `config.occurrence_context_limit` stored contexts per error
  (default 25), deleting the oldest first.
- **REQ-4.** Where `occurrence_context_limit` is 0, RED shall store no occurrence contexts.
- **REQ-5.** When an error or its occurrences are deleted (retention cleanup, `cleanup_resolved`,
  destroying the error), RED shall delete their stored contexts too.
- **REQ-6.** When the error page is opened for an occurrence that has a stored context, it shall
  show the breadcrumb, system-health and variable cards from that occurrence's context, and say
  which occurrence (and when) it is showing.
- **REQ-7.** When the error page is opened without an occurrence, or for one with no stored
  context, it shall show the error's latest snapshot exactly as today.
- **REQ-8.** The error page's occurrence list shall link each occurrence that has a stored context
  to the page for that occurrence.
- **REQ-9.** If the requested occurrence does not exist or belongs to a different error, then the
  error page shall show the error's latest snapshot and never another error's context.
- **REQ-10.** If storing an occurrence's context fails, then RED shall still record the error and
  the occurrence, and shall not raise in the host application.
- **REQ-11.** An occurrence's stored context shall hold the same values RED writes to the error
  row's snapshot for that capture: no field the row would not hold, nothing the row would filter.
- **REQ-12.** When a host upgrades from 0.15.x by running the installer and `db:migrate`, the
  context table shall exist in the error database (same or separate database) on SQLite,
  PostgreSQL and MySQL.
- **REQ-13.** The configuration guide shall document `occurrence_context_limit`, and the error-page
  docs shall describe viewing an earlier occurrence. [untested: prose, verified by reading]

## Out of scope
- The canonical event-envelope refactor (evidence-integrity §D8).
- Per-occurrence history of `request_params`, user, URL or user agent.
- Any change to how the error row's latest snapshot (C2) is refreshed.
- Backfilling history for occurrences recorded before the upgrade.
