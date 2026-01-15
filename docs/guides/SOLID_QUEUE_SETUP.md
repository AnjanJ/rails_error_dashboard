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

### 1. Generate Configuration

Use the generator to create a ready-to-use Solid Queue configuration:

```bash
rails generate rails_error_dashboard:solid_queue
```

This creates `config/queue.yml` with optimized settings for all environments.

### 2. Install Solid Queue

If not already installed (Rails 8.1+ includes it by default):

```bash
```bash
bundle add solid_queue
bin/rails solid_queue:install
bin/rails db:migrate
```

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

#### Development
```yaml
development:
  workers:
    - queues: error_notifications
      threads: 2          # Moderate concurrency for API calls
      processes: 1        # Single process (low resource usage)
      polling_interval: 1 # Check for jobs every second

    - queues: default
      threads: 3          # Higher concurrency for DB operations
      processes: 1
      polling_interval: 1
```

**Why these settings?**
- Low resource usage for local development
- 1-second polling is responsive enough for dev work
- 2-3 threads handle typical dev load

#### Production
```yaml
production:
  workers:
    - queues: error_notifications
      threads: 3          # More threads for external API calls
      processes: 1        # Keep processes low (API rate limits)
      polling_interval: 0.5

    - queues: default
      threads: 5          # Higher concurrency for DB writes
      processes: 2        # Multiple processes for throughput
      polling_interval: 0.5
```

**Why these settings?**
- 0.5s polling for near-real-time processing
- Multiple processes for horizontal scaling
- More threads on `default` queue (DB operations scale better than API calls)

#### Test
```yaml
test:
  workers:
    - queues: "*"       # Process all queues
      threads: 1
      processes: 1
      polling_interval: 0.1  # Fast polling for quick test execution
```

**Why these settings?**
- Single thread/process (deterministic test execution)
- Fast polling (tests complete quickly)
- Wildcard queue (simplifies test setup)

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
