# 0001: RED never writes another gem's files or runs another gem's installer

- **Date:** 2026-09-29. Status: accepted (the user approved the plan).

## Context

`rails g rails_error_dashboard:solid_queue` wrote its own `config/queue.yml`. The file drifted from
Solid Queue's format (workers, no dispatchers), and Solid Queue then started no dispatcher: no
delayed job ran in the host app. Every RED release up to 0.14.2 shipped it. The fix in 0.14.3 first
told users to run `bin/rails solid_queue:install`, which (in Solid Queue 1.7.0) rewrites
`production.rb` to use a separate `queue` database. Both are the same mistake: RED acting on files
another gem owns.

## Alternatives

1. RED owns templates for the job backends it supports, and keeps them in step.
2. RED never writes another gem's files or runs another gem's installer. It checks the app's config,
   says what it needs, and links to the other gem's docs.

## Case for 2

RED can't drift from a format it never writes. A job backend's installer can change without RED's
docs or generators going wrong. The check reaches every app, however its config was written.

## Case against 2

New users follow two sets of docs. RED can't offer RED-specific tuning (for example, dedicated
threads for `error_notifications`) as a one-command setup.

## Decision

2. It applies to Solid Queue now and to any job backend, scheduler or host-app config later:
`config/queue.yml`, `config/recurring.yml`, `bin/jobs`, `db/queue_schema.rb`,
`config/environments/*.rb`, `config/database.yml`, `config/puma.rb`. When RED's periodic jobs get
scheduling, it will be a documented snippet the user adds, not a write to `recurring.yml`. Enforced
by `spec/generators/generators_hands_off_spec.rb`.

**I would reverse this if** three or more users ask for a one-command, RED-specific job-backend
setup that a documented snippet can't give them.
