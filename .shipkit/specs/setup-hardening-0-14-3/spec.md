# Spec: Setup hardening (0.14.3)

> Spec accepted at commit `d75859b` on main (2026-09-28). Plan approved by the user the same day.
> The user chose to retire the Solid Queue generator rather than fix its template.

## Purpose

On 2026-09-28, three read-only audits of the setup and operations docs against v0.14.2 turned up
code bugs that no doc change can fix:

1. `rails g rails_error_dashboard:solid_queue` wrote a `config/queue.yml` with `workers:` and no
   `dispatchers:`. Solid Queue 1.7.0 only falls back to its default dispatcher when an environment
   section is empty, so no dispatcher ran. No delayed job ran, including the host app's own
   `retry_on wait:`. The workers also served only RED's two queues.
2. Uninstall (the `rails_error_dashboard:db:drop` task and the uninstall generator) knew 5 of the 13
   tables. The task dropped them in reverse order, so `error_logs` went before the tables that
   reference it. Both always used the primary connection.
3. `validate!` accepted `log_level = :fatal`, which the logger did not define. Every internal log
   call then raised.
4. A blank credential in development silently denied every login.
5. The installer claimed the dashboard also worked at `/error_dashboard`, and that async logging
   needed no worker.

`USE_SEPARATE_ERROR_DB` doing nothing on generator installs is handled in the docs, not here (see
design.md D4).

## Requirements (EARS)

Solid Queue:
- **REQ-1:** When `rails g rails_error_dashboard:solid_queue` runs, the generator shall not create or
  modify the Solid Queue config file.
- **REQ-2:** If an environment section of the Solid Queue config defines workers and no dispatchers,
  then the config check shall report that environment.
- **REQ-3:** If an environment section defines dispatchers and no workers, then the config check shall
  report that environment.
- **REQ-4:** If no worker in an environment section processes one of RED's queues (as the app names
  them), then the config check shall report the queue.
- **REQ-5:** If the Solid Queue config file cannot be read or rendered, then the config check shall
  report it as skipped and shall not raise.
- **REQ-6:** Where Solid Queue is loaded and its config file exists, `error_dashboard:verify` shall run
  the config check for every environment section, whatever the current queue adapter.

Uninstall:
- **REQ-7:** The uninstall plan shall list every table named `rails_error_dashboard_*` on the error
  database connection.
- **REQ-8:** The uninstall plan shall place every table that holds a foreign key before the table it
  references.
- **REQ-9:** When tables are dropped, the rake task and the uninstall generator shall drop them in plan
  order on `RailsErrorDashboard::ErrorLogsRecord.connection`.
- **REQ-10:** Where the adapter supports DDL transactions, dropping the tables shall be all-or-nothing.
- **REQ-11:** If `use_separate_database` is on and the error database connection is not the configured
  database, then the uninstall shall abort and name the missing database.yml entry.
- **REQ-12:** The uninstall generator shall drop the tables before it removes the initializer and the
  route.

Logger:
- **REQ-13:** `validate!` shall accept exactly the log levels the internal logger defines.
- **REQ-14:** The internal logger shall not raise, whatever `log_level` holds.
- **REQ-15:** While `log_level` is `:fatal`, the internal logger shall emit nothing.

Blank credentials:
- **REQ-16:** While in development with Basic auth, if a dashboard credential is blank, then
  `validate!` shall log a warning that names the empty variable (or the blank setting) and says every
  login will be denied.
- **REQ-17:** If a dashboard credential is blank, then `error_dashboard:verify` shall report a warning
  that says every login is denied.

Installer:
- **REQ-18:** The installer shall not state that the dashboard is served at `/error_dashboard`.
- **REQ-19:** The installer and the generated initializer shall state that async logging runs on the
  app's Active Job adapter and needs a worker for RED's queues.

Conditional (only if reproduced):
- **REQ-20:** When `error_dashboard:cleanup_resolved` deletes error logs, it shall first delete their
  dependent rows, in batches.

## Acceptance

Each requirement has a spec that fails on the v0.14.2 code for the requirement's reason, and passes
after its fix (see tasks.md).
