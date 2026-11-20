# Spec: 1.0 hardening (1.0.0-rc.2)

> Spec accepted at commit `4afd12db` on spec/hardening-1-0-rc2.
> Status: open
> Paths: lib/,app/,db/migrate/,config/locales/,spec/,test/pre_release/,bin/pre-release-test,docs/,README.md,rails_error_dashboard.gemspec,_getting_started/,.github/workflows/,.shipkit/decisions/,.shipkit/research/,.shipkit/specs/release-1-0-rc1/

## Purpose
Fix every finding of the independent 1.0.0-rc.1 review that held up on verification, before 1.x freezes
the behaviour. The review's evidence and the maintainer's answers are in `intake.md`. 1.0.0-rc.2 ships by
2026-12-11; work not ready by then ships in an rc.3 by 2026-12-17. 1.0.0 follows two quiet weeks, by
2026-12-31.

## User stories
- As a Rails developer deploying with Capistrano, I want an error to stay one group across releases, so
  that every deploy doesn't reset triage and send fresh alerts.
- As a Rails developer, I want two different bugs in one file to be two groups, so that fixing one doesn't
  hide the other.
- As a Rails developer, I want an error reported inside a transaction or a read-only block to be kept, and
  RED never to wait on a starved connection pool, so that RED records what happened without slowing my app.
- As an on-call engineer, I want an alert that failed to send to be retried, so that one Slack outage
  doesn't cost me the alert.
- As a team lead, I want the dashboard to record who resolved or muted an error from our login, not from a
  text box, so that the audit trail can be trusted.
- As an operator with a busy error, I want to keep its occurrences for a set number of days if I choose,
  so that the table stays a manageable size.

## Requirements (EARS)

### Grouping v2
- **REQ-1.** The fingerprint shall use the first app frame's path relative to `Rails.root`, so one file
  loaded from two release directories gives one fingerprint.
- **REQ-2.** When choosing the first app frame, the fingerprint shall skip frames whose path starts with
  `<internal:` and frames under Ruby's own library directory.
- **REQ-3.** The fingerprint shall include the first app frame's method name and shall not include its
  line number.
- **REQ-4.** When the exception is a `NameError` (including `NoMethodError`), the fingerprint shall
  include the exception's `name`.
- **REQ-5.** When a capture finds no open group with its v2 fingerprint and finds one with its v1
  fingerprint, RED shall count the capture on that group and store the v2 fingerprint on it.
- **REQ-6.** When an async job or a storm flush enqueued by 1.0.0-rc.1 or earlier, carrying only the v1
  identity, is processed, RED shall count it under v1 as it did before.
- **REQ-7.** Where `custom_fingerprint` returns a value, the fingerprint shall be the same as in
  1.0.0-rc.1.
- **REQ-8.** `docs/PUBLIC_API.md` shall state that the default grouping recipe is stable for all of 1.x
  and that the v1 fallback is removed only in 2.0. [untested: prose, verified by reading]

### Grouping window
- **REQ-9.** While an open group's last occurrence is less than 24 hours old, a matching capture shall be
  counted on that group, however long ago the group was first seen.
- **REQ-10.** When an open group's last occurrence is 24 hours old or more, a matching capture shall start
  a new group.
- **REQ-11.** The storm flush and the duplicate-create retry shall match groups by the same rule as
  REQ-9 and REQ-10.
- **REQ-12.** `docs/PLUGIN_SYSTEM.md` and the glossary shall describe when a new group starts.
  [untested: prose, verified by reading]

### Defaults and release hygiene
- **REQ-13.** The README and the guides shall say that async capture is the installer's default and sync is
  the library's default, and shall state sync capture's measured cost against the 5 ms budget.
  [untested: prose, verified by reading]
- **REQ-14.** The gemspec shall set the metadata `rubygems_mfa_required` to `"true"`.
- **REQ-15.** If a capture's `user_id` is an integer outside the `user_id` column's range, then RED shall
  store the capture with a nil `user_id`.
- **REQ-16.** A fresh install shall create the `user_id` columns as bigint, unless the host sets
  `primary_key_type`.

### Host conditions
Amended 2026-11-20 by spike S1 (`.shipkit/research/host-conditions-spike.md`; the decision is "Captures
wait for the host's transaction, on the shared connection" in `design.md`). The maintainer read the evidence
and accepted these terms on 2026-11-20:
- **The switch:** `config.isolate_capture_writes`, default `true`. With `false`, RED writes as in
  1.0.0-rc.1: on the host's shared connection, inside whatever transaction and role the reporting thread
  is in, waiting up to the pool's own `checkout_timeout`.
- **RED's connection timeout:** `config.capture_connection_timeout`, in seconds, default `0.1`: the longest a
  capture waits to lease a connection from a pool it writes through.
- **The pools a capture writes through:** RED's pool (`ErrorLogsRecord.connection_pool`, which is the host's
  own pool unless `use_separate_database` is on) for the sync write, and the host's pool
  (`ActiveRecord::Base.connection_pool`) for the async enqueue.
- **A held pool:** in a test, every connection of the pool the step writes through is checked out by other
  threads, and the reporting thread holds none.
- **REQ-17.** If a capture is reported inside a host transaction or savepoint that rolls back, then the
  captured error shall still be stored, in sync and in async mode.
- **REQ-18.** While the host prevents writes (`while_preventing_writes`, or a reading role with
  `prevent_writes`), a capture shall still be stored, through the writing role.
- **REQ-19.** If the database refuses RED's write (the adapter raises `ActiveRecord::StatementInvalid` or a
  subclass of it, such as `ActiveRecord::ReadOnlyError`, on RED's INSERT or UPDATE), then the capture shall
  be dropped without raising into the host.
- **REQ-20.** If RED cannot lease a connection from a pool it writes through within
  `capture_connection_timeout`, then the capture shall give up after that one wait and shall not try again.
- **REQ-21.** If looking up or creating the application record fails on a connection timeout, then the
  capture shall not wait for a second connection.
- **REQ-22.** Where the host turns the host-condition handling off by config, captures shall be written as
  in 1.0.0-rc.1.
- **REQ-51.** When a capture is reported inside an open host transaction, RED shall write or enqueue it only
  after that transaction and every enclosing one have ended, and shall record the time it was reported as
  its occurrence time.
- **REQ-52.** While 100 captures already wait on one host transaction, RED shall drop any further capture
  reported inside it, without raising.
- **REQ-53.** Where an async capture's enqueue runs after the response, RED shall not wait for a connection
  on the request thread for it.

### Data lifecycle
A **live** group, here, is one the retention job does not expire: `retention_days` is nil, or the group
was last seen less than `retention_days` ago (`RetentionCleanupJob.expired_scope`).
- **REQ-23.** Where `occurrence_retention_days` is set, the retention job shall delete, in batches, the
  occurrences older than that many days, from groups that are still live.
- **REQ-24.** While `occurrence_retention_days` is nil (the default), the retention job shall delete no
  occurrence of a live group.
- **REQ-25.** When occurrences are deleted by age, the group's `occurrence_count`, `first_seen_at` and
  `last_seen_at` shall not change.
- **REQ-26.** While `retention_days` is set and an error last seen more than `retention_days` plus 2 days
  ago still exists, the dashboard shall show a banner that names the retention job.
- **REQ-27.** When a user deletes errors in a batch, RED shall delete them and their dependents in batches,
  without loading each row.
- **REQ-28.** When a batch delete completes, RED shall dispatch `on_errors_batch_deleted` with the deleted
  ids.

### Notifications
- **REQ-29.** If a notification channel's send fails on a timeout, a refused connection, HTTP 429 or an
  HTTP 5xx, then its job shall raise so the job's retry runs.
- **REQ-30.** If a notification channel's send fails in any other way, then its job shall log the failure
  and finish without raising.
- **REQ-31.** When a notification job's retries are used up, RED shall release the notification's
  cooldown claim.
- **REQ-32.** Every webhook post shall carry a delivery id that is the same on every retry of that post.
- **REQ-33.** `docs/WEBHOOKS.md` shall say deliveries are at-least-once and how to drop duplicates by the
  delivery id. [untested: prose, verified by reading]
- **REQ-34.** When an issue creation fails, the issue-creation circuit breaker shall count one failure.
- **REQ-35.** When an issue creation fails because the error already has an issue or because issue
  tracking is not configured, the job shall not retry, in any locale.

### Audit actor
- **REQ-36.** Where the actor setting is configured, resolving, assigning, muting and their batch forms
  shall record the name the setting returns and ignore a name typed in the form.
- **REQ-37.** While the actor setting is not configured, or returns nil, those actions shall record the
  typed name and mark it as unverified.
- **REQ-38.** If the actor setting raises, then the action shall complete with the typed name marked as
  unverified.
- **REQ-39.** The error page shall show an unverified name marked as unverified.

### Dashboard and queries
- **REQ-40.** The keyboard shortcuts shall ignore a key pressed with Ctrl, Cmd or Alt.
- **REQ-41.** The keyboard shortcuts shall ignore keys typed into a `<select>`.
- **REQ-42.** Where the host's request has a CSP nonce, the layout's `<style>` tag shall carry it.
- **REQ-43.** Dashboard responses shall carry a content security policy that allows the dashboard's
  inline `style` attributes, and responses outside the dashboard shall keep the host's policy unchanged.
- **REQ-44.** The MTTR statistics shall be computed in the database without loading error rows.
- **REQ-45.** The error list's filter options shall be cached per application for at most 5 minutes, and
  cleared by the dashboard's own write actions. Capture does not clear them: by design, capture does no
  cache work (`error_log.rb:106-108`).
- **REQ-46.** Local-variable capture shall skip a frame because of where it is (outside `Rails.root`, in a
  gem, or in RED), not because its path contains `/ruby/` or `rails_error_dashboard`.
- **REQ-47.** The three built-in plugins shall describe themselves as examples.

### Migrations
- **REQ-48.** On PostgreSQL, when `index_error_logs_on_group_identity` exists but is invalid, a migration
  shall rebuild it, and running that migration again shall change nothing.
- **REQ-49.** Every migration added after 1.0.0-rc.1 that adds an index to an existing RED table shall
  build it concurrently on PostgreSQL.

### Chaos
- **REQ-50.** The pre-release chaos tests shall cover a deploy from two release directories, a report
  inside a transaction that rolls back, a report inside a write-prevented block, and a report with the
  connection pool held, on SQLite, PostgreSQL and MySQL, each under Rails 7.2, 8.0 and 8.1.

## Spikes (they decide requirements; no product code)
- **S1, host conditions.** Which mechanism stores a capture through a host rollback, through prevented
  writes and past a starved pool, on SQLite, PostgreSQL and MySQL, under Rails 7.2, 8.0 and 8.1; what it
  costs in database connections and capture time; how it is switched off. Done by 2026-12-04 to make rc.2.
  Its result confirms or amends REQ-17 to REQ-22. **Done 2026-11-20:** `.shipkit/research/host-conditions-spike.md`.
  It amended REQ-17, REQ-18 and REQ-20, added REQ-51 to REQ-53, and kept both setting names.
- **S2, silent failures.** What changes if a failed capture becomes visible: how often RED's failure lines
  can fire, what they cost on the capture path, and whether they print personal data (the failure line
  prints the capture's context today). The options include the `log_level` default and a failure count on
  the health page. No requirement is written until the maintainer has read the evidence.

## Out of scope
See `intake.md`: roles, rewriting inline `style` attributes, editing shipped migrations, the MySQL
unique-index gap, `ErrorHashGenerator.from_attributes`, stars and contributor counts.
