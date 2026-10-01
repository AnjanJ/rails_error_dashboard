---
layout: default
title: "Solid Queue Setup Guide"
order: 5
---

# Solid Queue Setup Guide

This guide covers running RailsErrorDashboard's jobs on **Solid Queue**, the default Active Job backend in Rails 8.

## What is Solid Queue?

Solid Queue is a **database-backed Active Job adapter**, the default since Rails 8.0. It provides:
- ✅ No external dependencies (Redis, etc.)
- ✅ ACID guarantees for job processing
- ✅ Built-in job monitoring and inspection
- ✅ Simple deployment (no additional services)
- ✅ Works with any Rails-supported database

## What RED needs from Solid Queue

RED's jobs run on your app's own Active Job adapter. RED writes nothing for Solid Queue: no config, no schedule, no schema. With Solid Queue, three things must be true in every environment that runs jobs:

1. **A dispatcher.** Every environment section of `config/queue.yml` needs a `dispatchers:` block. A section with `workers:` and no `dispatchers:` starts no dispatcher, so no delayed job ever runs: RED's retries, and your app's own `retry_on wait:` and `perform_later(wait:)`.
2. **A worker for RED's queues.** RED uses `default` and `error_notifications` (with your `queue_name_prefix`, if you set one). A `"*"` worker processes them, and your app's other queues too.
3. **A running worker process**: `bin/jobs`, or Solid Queue's Puma plugin (`SOLID_QUEUE_IN_PUMA=1`). Without one, errors logged asynchronously wait in the queue and are never recorded.

Check your config with:

```bash
bin/rails error_dashboard:verify
```

It reports "Solid Queue config... OK", or the problem in each environment. It checks the file, so it can't tell whether a worker process is running. The line appears only when Solid Queue is in your bundle and `config/queue.yml` exists.

## Quick Start

### 1. Set up Solid Queue

Rails 8 apps come with Solid Queue set up. For an older app, follow [Solid Queue's installation guide](https://github.com/rails/solid_queue#installation). RED adds nothing to it, and its generated `config/queue.yml` (a `"*"` worker and a dispatcher) already covers everything above.

> **Already using Solid Queue? Edit `config/queue.yml`; don't re-run Solid Queue's installer to fix it.** As of Solid Queue 1.7.0, `bin/rails solid_queue:install` also rewrites the queue settings in `config/environments/production.rb` to use a separate `queue` database. That breaks an app that runs Solid Queue on its main database. The installer also offers to overwrite `config/recurring.yml`, where your scheduled jobs live.

> **Ran `rails generate rails_error_dashboard:solid_queue` before 0.14.3?** It wrote a `config/queue.yml` with workers and no `dispatchers:`. With that file Solid Queue runs no dispatcher, so no delayed job ever runs, your app's own included. Its workers also served only RED's two queues. Replace the file's contents with the [example below](#environment-specific-settings), keeping any other environment sections you have (`staging:`, for example) as `<<: *default`. Since 0.14.3 the generator writes nothing; it only checks your config.

### 2. Check Your Config

```bash
bin/rails error_dashboard:verify
```

Run it again after any change to `config/queue.yml`: it checks the section for each environment your app defines in `config/environments/`.

Solid Queue 1.6+ can also check its own config: `RAILS_ENV=production bin/jobs check`. That catches other mistakes, such as a typo in `config/recurring.yml`. It passes a section with workers and no dispatcher, though, so run both.

### 3. Configure ActiveJob Adapter

In `config/environments/production.rb` (a new Rails 8 app already has this):

```ruby
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }  # with a separate queue database
```

Set it in production only, unless you have also set up Solid Queue's database for development and
test. Solid Queue's installer sets it up for production only, and with the adapter set in an
environment that has no queue tables, every job fails to enqueue.

### 4. Enable Async Logging

In `config/initializers/rails_error_dashboard.rb` (the installer already writes this):

```ruby
RailsErrorDashboard.configure do |config|
  config.async_logging = true
end
```

RED's jobs then run on whatever `config.active_job.queue_adapter` says. `config.async_adapter` is
only checked for a valid value; it doesn't choose the backend.

### 5. Start Workers

In development:
```bash
bin/jobs
```

In production (using a process manager like systemd or Supervisor):
```bash
bundle exec rake solid_queue:start
```

## Configuration Details

### Queue Structure

RailsErrorDashboard uses two queues:

1. **`default`** - async error logging, Discord, PagerDuty and webhook notifications, storm and
   baseline alerts, the scheduled jobs, and periodic flushes of buffered counts
2. **`error_notifications`** - Slack and email notifications, and the issue-tracker jobs

### Scheduled Jobs

Nothing in the gem schedules `RetentionCleanupJob`, `BaselineCalculationJob` or
`ScheduledDigestJob`. With Solid Queue, add them to `config/recurring.yml`: see
[Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs) for the entries.
Recurring tasks run only where Solid Queue's scheduler runs: `bin/jobs`, or Puma with
`SOLID_QUEUE_IN_PUMA`.

### Environment-Specific Settings

Keep Solid Queue's own structure. **Every environment section needs a `dispatchers:` block**: a section that lists `workers:` and no `dispatchers:` runs no dispatcher, so no delayed job or retry ever runs, your app's included. Keep a `"*"` worker so your app's other queues are processed too.

If RED's notifications need their own threads, add a worker for `error_notifications` next to the `"*"` one:

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"                     # every queue: your app's and RED's
      threads: 3
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 0.1
    - queues: error_notifications     # optional: dedicated threads for Slack, email and issue jobs
      threads: 2
      polling_interval: 0.5

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

Run `bin/rails error_dashboard:verify` after editing.

## Performance Tuning

### Thread Count

**For `default` queue (database operations):**
- Start with the example's 3 threads
- Increase if you see job backlogs during error spikes
- Each thread needs a database connection: see [Database Connection Pool](#database-connection-pool)

**For `error_notifications` queue (external APIs):**
- Start with 2 or 3 threads
- Too many threads can hit API rate limits (Slack, PagerDuty, etc.)
- External APIs are slow - more threads = more concurrent API calls

### Process Count

**Multiple processes provide:**
- Better CPU utilization (true parallelism)
- Fault isolation (one process crash doesn't stop all jobs)
- Higher throughput for CPU-bound jobs

**Guidelines:**
- `default` queue: 1-2 processes in production
- `error_notifications` queue: Usually 1 process is sufficient
- Monitor memory usage (each process loads full Rails app)

### Polling Interval

**Shorter intervals (0.1 - 0.5s):**
- ✅ Near real-time job execution
- ❌ More database queries (polling overhead)

**Longer intervals (1 - 5s):**
- ✅ Lower database load
- ❌ Slower job pickup (higher latency)

Solid Queue's own template uses 0.1s for workers and 1s for the dispatcher, as in the example
above. Raise the worker interval if polling load matters more than how quickly jobs start.

## Database Connection Pool

Solid Queue uses database connections for job processing. `pool` in `config/database.yml` is per
process, so size it for the biggest single process:

- **The queue database:** each worker process needs `pool` ≥ its threads + 2.
  `bin/jobs check` (Solid Queue 1.6+) warns when it is smaller.
- **RED's database:** RED's jobs write errors through RED's connection: your main database, or
  the error database with a separate one. Its `pool` must cover the worker's threads too.

The total across every process (workers, web servers, consoles) is what your database server's
`max_connections` has to allow.

## Monitoring

### Check Job Status

```ruby
# Rails console
SolidQueue::ReadyExecution.count      # waiting for a worker
SolidQueue::ScheduledExecution.count  # waiting for their time (retries, wait:)
SolidQueue::FailedExecution.count     # failed for good
SolidQueue::Job.where(queue_name: "default", finished_at: nil).count
SolidQueue::Process.pluck(:kind, :hostname, :last_heartbeat_at)  # running processes
```

`SolidQueue::Job` also keeps finished jobs (Solid Queue's `preserve_finished_jobs` is on by
default), so count unfinished ones with `finished_at: nil`.

### View Failed Jobs

```ruby
SolidQueue::Job.failed.each do |job|
  puts "#{job.class_name}: #{job.failed_execution.exception_class} #{job.failed_execution.message}"
end
```

### Retries

Solid Queue doesn't retry failed jobs by itself; retries come from each job's `retry_on`.

- Most of RED's jobs retry three times with a growing delay, then log
  `Job ... discarded after 3 attempts` and are dropped. They don't stay in the failed set.
- The issue-tracker jobs (create, close, reopen and comment on issues) retry and then fail
  normally, so they do end up in `SolidQueue::Job.failed`. Retry them with
  `job.failed_execution.retry`, or from Mission Control.
- Delayed retries need a dispatcher (see the top of this page).

## Deployment

### Systemd Service (Linux)

Create `/etc/systemd/system/rails-jobs.service`:

```ini
[Unit]
Description=Rails Solid Queue Workers
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/myapp
Environment=RAILS_ENV=production
ExecStart=/usr/local/bin/bundle exec rake solid_queue:start
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable rails-jobs
sudo systemctl start rails-jobs
sudo systemctl status rails-jobs
```

### Docker

```dockerfile
# Dockerfile
FROM ruby:3.4

# ... app setup ...

# Start both web and workers
CMD ["foreman", "start"]
```

```procfile
# Procfile
web: bundle exec rails server
worker: bundle exec rake solid_queue:start
```

### Heroku

Add to `Procfile`:
```procfile
web: bundle exec rails server
worker: bundle exec rake solid_queue:start
```

Scale workers:
```bash
heroku ps:scale worker=1
```

## Troubleshooting

### Jobs not processing

1. **Check workers are running:**
   ```bash
   ps aux | grep solid-queue
   ```

2. **Check logs:** Solid Queue logs to your app's log, for example `log/production.log`.

3. **Verify configuration:**
   ```ruby
   # Rails console
   Rails.application.config.active_job.queue_adapter
   # => :solid_queue
   ```

### High database load

1. **Increase polling interval** (reduce query frequency)
2. **Add database indexes** on `solid_queue_jobs` table
3. **Use connection pooling** properly

### Memory usage high

1. **Reduce process count** (each process loads full Rails app)
2. **Reduce thread count** (threads share memory but still consume)
3. **Monitor with** `ps aux` or `htop`

### Job backlog building up

1. **Increase thread count** for affected queue
2. **Add more processes** (horizontal scaling)
3. **Check for slow external APIs** (notifications)

## Solid Queue vs Sidekiq

| Feature | Solid Queue | Sidekiq |
|---------|-------------|---------|
| **Dependencies** | Database only | Redis required |
| **Setup complexity** | Simple | Moderate |
| **Performance** | Good (DB-backed) | Excellent (memory-backed) |
| **Reliability** | Excellent (ACID) | Very good |
| **Monitoring** | Rails queries, Mission Control | Web UI (free) |
| **Cost** | Free | Free + optional Pro |
| **Best for** | Small-medium apps, simple deployments | High-volume, performance-critical |

**Recommendation:**
- **Use Solid Queue** for most Rails 8.0+ apps (simpler, fewer dependencies)
- **Use Sidekiq** if you need maximum performance or already use Redis

## Additional Resources

- [Solid Queue GitHub](https://github.com/rails/solid_queue)
- [Rails 8.0 Release Notes](https://guides.rubyonrails.org/8_0_release_notes.html)
- [ActiveJob Documentation](https://guides.rubyonrails.org/active_job_basics.html)
