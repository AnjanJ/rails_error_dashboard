---
layout: default
title: "Running Rails Error Dashboard in Production"
order: 5
---

# Running Rails Error Dashboard in Production

The installer sets RED up for development. Before your first production deploy, go through this
list. Each item is something RED needs from your app's own setup. If one is missing, RED doesn't
stop the app; it loses errors, notifications or scheduled cleanups without telling you.

1. [Run a worker for RED's jobs](#1-run-a-worker-for-reds-jobs)
2. [Schedule the periodic jobs](#2-schedule-the-periodic-jobs)
3. [Run migrations on every deploy](#3-run-migrations-on-every-deploy)
4. [Separate database: add it to every environment](#4-separate-database-add-it-to-every-environment)
5. [Docker: set SECRET_KEY_BASE_DUMMY only on the build step](#5-docker-set-secret_key_base_dummy-only-on-the-build-step)
6. [Set the dashboard credentials](#6-set-the-dashboard-credentials)

Then run `bin/rails error_dashboard:verify` in production. It checks the configuration, the
database, its tables and (with a separate database) its `config/database.yml` entry, the
credentials, json 3 against your Rails version and, on Solid Queue, `config/queue.yml`. It can't
tell whether a worker or a scheduler is running. Since 0.14.4 the dashboard also shows a banner when
Solid Queue's config would never run RED's jobs.

## 1. Run a worker for RED's jobs

The installer turns on `config.async_logging`, so every captured error is saved by a background
job. Notifications are always background jobs. They all run on your app's Active Job adapter,
`config.active_job.queue_adapter`. (`config.async_adapter` in RED's initializer is only checked
for a valid value; it doesn't choose the backend.)

RED's jobs use two queues, and the worker has to process both:

| Queue | Jobs |
|---|---|
| `default` | saving errors (async logging), Discord, PagerDuty and webhook notifications, the storm and baseline alerts, the scheduled jobs below, and periodic flushes of buffered counts |
| `error_notifications` | Slack and email notifications, and the issue-tracker jobs |

If your app sets `config.active_job.queue_name_prefix`, the queue names carry that prefix.

- **Solid Queue** (the Rails 8 default): the `config/queue.yml` that Solid Queue's installer
  writes has `queues: "*"`, which covers both queues. Run `bin/jobs` as its own process, or set
  `SOLID_QUEUE_IN_PUMA=1` to run it inside Puma (a new Rails 8 app's `config/puma.rb` has the
  plugin line for it). See the [Solid Queue Setup Guide](/rails_error_dashboard/docs/guides/solid-queue-setup/).
- **Sidekiq**: Sidekiq only processes `default` unless told otherwise. Start it with
  `bundle exec sidekiq -q default -q error_notifications`, or list both queues in
  `config/sidekiq.yml`.
- **Rails' built-in `:async` adapter**, which is what you get when no adapter is set (the Rails 7
  default): jobs run in a thread pool inside each web process, and any job still queued when the
  process restarts, on every deploy for example, is lost.

Without a worker, set `config.async_logging = false`. Errors are then saved during the request
that raised them. Notifications still need a worker.

## 2. Schedule the periodic jobs

Nothing in the gem schedules these three jobs. Run them from your app's scheduler:

| Job | Without it |
|---|---|
| `RailsErrorDashboard::RetentionCleanupJob` | Nothing is ever deleted. It deletes errors not seen for `config.retention_days` (90 by default, `nil` keeps everything). |
| `RailsErrorDashboard::BaselineCalculationJob` | No baselines are calculated, so baseline alerts never fire. |
| `RailsErrorDashboard::ScheduledDigestJob` | No digest emails. It sends only when `config.enable_scheduled_digests` is on and there are recipients. |

With Solid Queue, add them to `config/recurring.yml`, under the same environment key as the tasks
already there:

```yaml
production:
  red_retention_cleanup:
    class: RailsErrorDashboard::RetentionCleanupJob
    schedule: every day at 3am
  red_baselines:
    class: RailsErrorDashboard::BaselineCalculationJob
    schedule: every day at 4am
  red_digest:
    class: RailsErrorDashboard::ScheduledDigestJob
    args: [ { period: "daily" } ]
    schedule: every day at 8am
```

For a weekly digest, use `args: [ { period: "weekly" } ]` and `schedule: every monday at 8am`.
Recurring tasks run only in the process that runs Solid Queue's scheduler: `bin/jobs`, or Puma with
`SOLID_QUEUE_IN_PUMA`. On Solid Queue 1.6 and later, `bin/jobs check` validates the file.

With cron, or any scheduler that runs a command, use `bin/rails runner`. The jobs then run in that
process, with no worker involved:

```sh
bin/rails runner 'RailsErrorDashboard::RetentionCleanupJob.perform_now'
bin/rails runner 'RailsErrorDashboard::BaselineCalculationJob.perform_now'
bin/rails runner 'RailsErrorDashboard::ScheduledDigestJob.perform_now(period: "daily")'
```

Don't schedule the `error_dashboard:retention_cleanup` rake task: it asks for confirmation before
deleting, so it can't run unattended.

## 3. Run migrations on every deploy

Every RED upgrade can add migrations. Run [the upgrade](/rails_error_dashboard/docs/upgrading/#the-upgrade) on your machine,
commit the new migration files, and make the deploy run `bin/rails db:migrate` or
`bin/rails db:prepare`. Both migrate the error database too, when it has an entry in production's
`config/database.yml`. See [Deploying](/rails_error_dashboard/docs/upgrading/#deploying).

## 4. Separate database: add it to every environment

With `config.use_separate_database = true`, every environment the app boots in needs the error
database in `config/database.yml`, test included:

```yaml
production:
  primary:
    <<: *default
    database: myapp_production
  error_dashboard:
    <<: *default
    database: myapp_errors_production
    migrations_paths: db/error_dashboard_migrate
```

If an environment has no `error_dashboard` entry, RED logs an error at boot and uses the main
database, which has no RED tables, so that environment's errors are not recorded anywhere. See the
[Database Setup Guide](/rails_error_dashboard/docs/guides/database-options/).

## 5. Docker: set SECRET_KEY_BASE_DUMMY only on the build step

When `SECRET_KEY_BASE_DUMMY` is set, RED assumes a build step with no database and turns off
error capture. The Dockerfile of a new Rails app sets it on the precompile command only, which is
right:

```dockerfile
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

Never set it as an `ENV` line in the image or in the runtime environment: the app then runs, and
no error is ever captured. RED itself needs no asset precompilation.

## 6. Set the dashboard credentials

Outside `development` and `test`, RED refuses to boot with the default credentials or a blank one.
Set `ERROR_DASHBOARD_USER` and `ERROR_DASHBOARD_PASSWORD`, or use your own authentication with
`authenticate_with`. See [Dashboard Credentials](/rails_error_dashboard/docs/guides/configuration/#dashboard-credentials).
