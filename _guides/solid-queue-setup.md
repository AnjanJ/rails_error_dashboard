---
layout: default
title: "Solid Queue Setup Guide"
order: 5
---

# Solid Queue Setup Guide

This guide covers how to configure **Solid Queue** (Rails 8.1+ default) for optimal performance with RailsErrorDashboard.

## What is Solid Queue?

Solid Queue is a **database-backed Active Job adapter** introduced in Rails 8.1. It provides:
- ✅ No external dependencies (Redis, etc.)
- ✅ ACID guarantees for job processing
- ✅ Built-in job monitoring and inspection
- ✅ Simple deployment (no additional services)
- ✅ Works with any Rails-supported database

## Quick Start

### 1. Install Solid Queue

Rails 8.0+ apps already have it. Otherwise:

```bash
bundle add solid_queue
bin/rails solid_queue:install
bin/rails db:prepare
```

`solid_queue:install` writes `config/queue.yml` with a `"*"` worker and a dispatcher. That already processes RED's queues (`default` and `error_notifications`), so RED needs no config of its own.

### 2. Check Your Config

```bash
bin/rails error_dashboard:verify
```

It reports "Solid Queue config... OK", or the problem in each environment.

> **Ran `rails generate rails_error_dashboard:solid_queue` before 0.14.3?** It wrote a `config/queue.yml` with workers and no `dispatchers:`. With that file Solid Queue runs no dispatcher, so no delayed job ever runs: your app's own `retry_on wait:` and `perform_later(wait:)` included. Its workers also served only RED's two queues. Replace the file with Solid Queue's own template (`bin/rails solid_queue:install`). Since 0.14.3 the generator writes nothing; it only checks your config.

### 3. Configure ActiveJob Adapter

In `config/application.rb` or environment-specific config:

```ruby
# For all environments
config.active_job.queue_adapter = :solid_queue

# Or environment-specific in config/environments/production.rb
config.active_job.queue_adapter = :solid_queue
```

### 4. Enable Async Logging

In `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  config.async_logging = true
  config.async_adapter = :solid_queue
end
```

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

1. **`default`** - Async error logging (high volume, fast database operations)
2. **`error_notifications`** - External notifications (lower volume, slower API calls)

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

Run `bin/rails error_dashboard:verify` after editing: it checks every environment in the file.

## Performance Tuning

### Thread Count

**For `default` queue (database operations):**
- Start with 5 threads
- Increase if you see job backlogs during error spikes
- Database connection pool must be >= thread count

**For `error_notifications` queue (external APIs):**
- Start with 3 threads
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

**Recommendations:**
- Production: 0.5s (good balance)
- Development: 1s (lower overhead)
- Test: 0.1s (fast test execution)

## Database Connection Pool

Solid Queue uses database connections for job processing. Ensure your connection pool is large enough:

```ruby
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>
```

**Formula:**
```text
Required connections = (threads_per_worker × processes) + web_server_threads + 5
```

**Example:**
- Default queue: 5 threads × 2 processes = 10
- Error notifications: 3 threads × 1 process = 3
- Web server: 5 threads
- Buffer: 5
- **Total: 23 connections minimum**

## Monitoring

### Check Job Status

```bash
# Rails console
SolidQueue::Job.pending.count
SolidQueue::Job.failed.count
SolidQueue::Job.where(queue_name: 'default').count
```

### View Failed Jobs

```ruby
SolidQueue::Job.failed.each do |job|
  puts "#{job.class_name}: #{job.exception_message}"
end
```

### Retry Failed Jobs

Solid Queue automatically retries failed jobs with exponential backoff.

Configuration in `config/solid_queue.yml`:
```yaml
production:
  max_retries: 5
  retry_delay: 10  # seconds
```

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
   ps aux | grep solid_queue
   ```

2. **Check logs:**
   ```bash
   tail -f log/solid_queue.log
   ```

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
| **Monitoring** | Rails queries | Web UI (paid) |
| **Cost** | Free | Free + optional Pro |
| **Best for** | Small-medium apps, simple deployments | High-volume, performance-critical |

**Recommendation:**
- **Use Solid Queue** for most Rails 8.1+ apps (simpler, fewer dependencies)
- **Use Sidekiq** if you need maximum performance or already use Redis

## Additional Resources

- [Solid Queue GitHub](https://github.com/basecamp/solid_queue)
- [Rails 8.1 Release Notes](https://edgeguides.rubyonrails.org/8_1_release_notes.html)
- [ActiveJob Documentation](https://guides.rubyonrails.org/active_job_basics.html)
