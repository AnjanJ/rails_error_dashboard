---
layout: default
title: "Multi-App Performance Monitoring"
order: 1
---

# Multi-App Performance Monitoring

This guide covers performance monitoring and optimization for Rails Error Dashboard's multi-app support feature.

## Architecture Overview

Multi-app support is designed for high-concurrency scenarios with multiple Rails applications writing errors simultaneously to a shared database.

### Key Design Decisions

1. **Row-Level Locking**: Uses pessimistic locking scoped to `(application_id, error_hash)` - apps never block each other
2. **Cached Application Lookups**: each app's id is cached by name for 1 hour, so the lookup by name is skipped
3. **Composite Indexes**: Optimized indexes on `[application_id, occurred_at]` and `[application_id, resolved]`
4. **Per-App Deduplication**: Error hashes include application_id to track same errors independently across apps
5. **One Row per Write**: each write locks a single error row. Two processes creating the same new error at once are stopped by a unique index on the error group (PostgreSQL and SQLite) and a retry on `RecordNotUnique`

## Database Performance

### Index Usage Monitoring (PostgreSQL)

Check if multi-app indexes are being used effectively:

```sql
-- Index usage statistics
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan as scans,
  idx_tup_read as tuples_read,
  idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE tablename = 'rails_error_dashboard_error_logs'
  AND (indexname LIKE '%application%' OR indexname LIKE '%\_app\_%')
ORDER BY idx_scan DESC;
```

**Expected Results**:
- `index_rails_error_dashboard_error_logs_on_application_id` should have high scan count
- `index_error_logs_on_app_occurred` should be used for time-based queries
- `index_error_logs_on_app_resolved` should be used for filtering unresolved errors

If scan counts are low (<100), the indexes may not be used. Check:
1. Are you filtering by application_id?
2. Is the query planner choosing a different strategy? (Run `EXPLAIN ANALYZE`)

### Slow Query Detection

Find slow queries involving applications:

```sql
-- Requires pg_stat_statements extension
SELECT
  query,
  calls,
  total_exec_time / calls as avg_time_ms,
  min_exec_time as min_ms,
  max_exec_time as max_ms,
  stddev_exec_time as stddev_ms
FROM pg_stat_statements
WHERE query LIKE '%rails_error_dashboard_error_logs%'
  AND query LIKE '%application_id%'
ORDER BY avg_time_ms DESC
LIMIT 20;
```

**Optimization Targets**:
- Average query time < 10ms for error writes
- Average query time < 50ms for dashboard queries
- Max query time < 500ms for analytics

### Buffer Cache Hit Rate (PostgreSQL)

This measures PostgreSQL's own buffer cache for the applications table, not `Rails.cache`:

```sql
-- PostgreSQL cache hit ratio
SELECT
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / NULLIF((sum(heap_blks_hit) + sum(heap_blks_read)), 0) as cache_ratio
FROM pg_statio_user_tables
WHERE relname = 'rails_error_dashboard_applications';
```

**Target**: Cache ratio > 0.99 (99%+)

If lower:
- Applications table should be tiny (usually <100 rows)
- All reads should hit cache

RED's `Rails.cache` entry (1-hour TTL) saves the lookup by name. A cache hit still loads the
application row by id, so it doesn't remove the database round trip.

### Lock Monitoring

Check for lock contention between applications:

```sql
-- Active locks on error_logs table
SELECT
  l.pid,
  l.mode,
  l.granted,
  a.application_name,
  a.query_start,
  a.state,
  substring(a.query, 1, 100) as query
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.relation = 'rails_error_dashboard_error_logs'::regclass
ORDER BY l.granted, a.query_start;
```

**Expected Behavior**:
- Most locks should be `granted = true`
- `RowShareLock` and `RowExclusiveLock` are normal
- `AccessExclusiveLock` (table-level) should NEVER appear during error logging

If you see ungranted locks:
1. Check for long-running transactions
2. Verify row-level locking is working (`FindOrIncrementError#find_unresolved` uses `.lock`)
3. Look for deadlocks in PostgreSQL logs

### Deadlock Detection

```sql
-- Check PostgreSQL logs for deadlocks
-- In postgresql.conf: log_lock_waits = on, deadlock_timeout = 1s

-- Or read the deadlock counter for this database
SELECT deadlocks FROM pg_stat_database
WHERE datname = current_database();
```

**Target**: Zero deadlocks

Our design prevents deadlocks by:
- Applications table is READ-ONLY after setup
- Error writes lock single row only
- A unique index on the error group (PostgreSQL and SQLite) plus a retry on `RecordNotUnique`
  stops duplicate groups

## Rails Application Monitoring

### Cache Performance

Monitor Rails cache for application lookups:

```ruby
# In Rails console. Deletes only this entry: Rails.cache.clear would empty your
# whole app's cache.
key = "error_dashboard/application_id/TestApp"
Rails.cache.delete(key)
app1 = RailsErrorDashboard::Application.find_or_create_by_name("TestApp")
app2 = RailsErrorDashboard::Application.find_or_create_by_name("TestApp") # Should hit cache

# Verify cache: the entry holds the application's id
Rails.cache.read(key)  # => app1.id
```

**Expected**:
- First call: lookup by name (or create)
- Second call: cache hit (within 1 hour), then a lookup by id
- With a null cache store (Rails 7 apps in development, unless you run `bin/rails dev:cache`), nothing is cached

### Query Object Performance

Measure analytics query performance by application:

```ruby
# Benchmark dashboard stats
require 'benchmark'

apps = RailsErrorDashboard::Application.pluck(:id).sample(5)

Benchmark.bm(20) do |x|
  x.report("All apps:") do
    RailsErrorDashboard::Queries::DashboardStats.call
  end

  apps.each do |app_id|
    x.report("App #{app_id}:") do
      RailsErrorDashboard::Queries::DashboardStats.call(application_id: app_id)
    end
  end
end
```

**Targets**:
- All apps query: < 100ms
- Single app query: < 50ms

### Error Write Performance

Benchmark error logging with multiple apps:

```ruby
require 'benchmark'

apps = 5.times.map { |i| RailsErrorDashboard::Application.create!(name: "BenchApp#{i}") }

Benchmark.bm(20) do |x|
  x.report("Sequential writes:") do
    100.times do
      app = apps.sample
      RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(
        "test_#{rand(10)}",
        application_id: app.id,
        error_type: "TestError",
        message: "Benchmark test",
        occurred_at: Time.current
      )
    end
  end

  x.report("Concurrent writes:") do
    threads = 10.times.map do
      Thread.new do
        10.times do
          app = apps.sample
          RailsErrorDashboard::ErrorLog.find_or_increment_by_hash(
            "concurrent_#{rand(10)}",
            application_id: app.id,
            error_type: "ConcurrentError",
            message: "Thread test",
            occurred_at: Time.current
          )
        end
      end
    end
    threads.each(&:join)
  end
end
```

**Targets**:
- Sequential: 5-10ms per write
- Concurrent: No deadlocks, similar per-write time
- Should see occurrence_count increments (not duplicates)

## Production Monitoring

### Metrics to Track

1. **Error Write Latency**
   - P50, P95, P99 for `LogError.call`
   - Target: P95 < 50ms, P99 < 200ms

2. **Application Cache Hit Rate**
   - Percentage of `find_or_create_by_name` that hit cache
   - Target: > 95%

3. **Query Performance**
   - Dashboard stats query time
   - Analytics query time
   - Filtering query time
   - Target: All < 100ms P95

4. **Database Metrics**
   - Lock wait time
   - Deadlock count (should be 0)
   - Index scan ratio (vs sequential scans)

### New Relic / APM Integration

```ruby
# In config/initializers/rails_error_dashboard.rb

# Count new and reopened errors per application (error_logged doesn't fire for
# other recurrences). RED's own events are sent after the write, so their
# duration is about zero.
ActiveSupport::Notifications.subscribe("error_logged.rails_error_dashboard") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  app_name = event.payload[:error_log].application&.name
  NewRelic::Agent.increment_metric("Custom/ErrorDashboard/Application/#{app_name}")
end

# Time the write itself (async logging): Active Job reports each job's duration
ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  next unless event.payload[:job].is_a?(RailsErrorDashboard::AsyncErrorLoggingJob)

  NewRelic::Agent.record_metric("Custom/ErrorDashboard/LogError", event.duration)
end

# Instrument find_or_create_by_name
RailsErrorDashboard::Application.class_eval do
  def self.find_or_create_by_name_with_instrumentation(name)
    ActiveSupport::Notifications.instrument("application.find_or_create", application: name) do
      find_or_create_by_name_without_instrumentation(name)
    end
  end

  class << self
    alias_method :find_or_create_by_name_without_instrumentation, :find_or_create_by_name
    alias_method :find_or_create_by_name, :find_or_create_by_name_with_instrumentation
  end
end
```

### Alerting Thresholds

Set up alerts for:

1. **High Error Write Latency**
   - Alert if P95 > 200ms for 5 minutes
   - Action: Check database load, slow queries

2. **Cache Miss Rate**
   - Alert if cache hit rate < 90% for 10 minutes
   - Action: Check Rails cache backend, memory

3. **Dashboard Query Slowness**
   - Alert if dashboard stats > 500ms
   - Action: Check error log count, consider archiving old errors

4. **Lock Contention**
   - Alert if lock wait events > 10/minute
   - Action: Check for long transactions, review locking strategy

## Performance Checklist

Use this checklist to verify multi-app performance:

### Database Layer

- [ ] Applications table index on `name` (unique)
- [ ] Error logs index on `application_id`
- [ ] Composite index on `[application_id, occurred_at]`
- [ ] Composite index on `[application_id, resolved]`
- [ ] Foreign key constraint exists
- [ ] `pg_stat_statements` enabled (PostgreSQL)
- [ ] Index scan ratio > 95%
- [ ] Cache hit ratio > 99%
- [ ] Zero deadlocks in production

### Rails Application Layer

- [ ] Application lookups use `find_or_create_by_name` (cached)
- [ ] Cache backend configured (Redis, Memcached, or memory)
- [ ] Cache expiry set to 1 hour
- [ ] Query objects use `base_scope` helper
- [ ] All dashboard queries scoped by application_id
- [ ] Row-level locking in `FindOrIncrementError` (which `ErrorLog.find_or_increment_by_hash` calls)
- [ ] Error hash includes application_id

### Monitoring

- [ ] APM tracking for error writes
- [ ] Dashboard for cache hit rate
- [ ] Alerts for slow queries
- [ ] Alerts for lock contention
- [ ] Periodic index usage review
- [ ] Weekly deadlock check

## Troubleshooting

### Problem: Slow Error Writes (>200ms)

**Diagnosis**:
```sql
-- Check if indexes are used
EXPLAIN ANALYZE
SELECT * FROM rails_error_dashboard_error_logs
WHERE application_id = 1 AND error_hash = 'abc123' AND resolved = false;
```

The plan should use an existing index (`index_error_logs_on_group_identity` on PostgreSQL and
SQLite, `index_error_logs_on_hash_resolved_occurred` on all three). Don't add another: the
fingerprint already includes the application.

**Solutions**:
1. Check every RED migration has run: `bin/rails db:migrate:status | grep -i 'rails error dashboard'`
2. Check database load and connection pool
3. Enable async logging in config

### Problem: High Cache Miss Rate

**Diagnosis**:
```ruby
# Check if cache backend is working
Rails.cache.write("test", "value")
Rails.cache.read("test") # Should return "value"
```

**Solutions**:
1. Check Rails cache backend (config/environments/production.rb)
2. Verify cache size limits aren't being hit
3. Check if cache is being cleared too frequently

### Problem: Deadlocks

**Diagnosis**:
```bash
# Check PostgreSQL logs
grep "deadlock detected" /var/log/postgresql/postgresql-*.log
```

**Solutions**:
1. Verify `FindOrIncrementError#find_unresolved` uses `.lock`
2. Check for custom queries that bypass row-level locking
3. Review transaction isolation level (should be READ COMMITTED)

### Problem: Ungranted Locks

**Diagnosis**:
```sql
SELECT * FROM pg_locks WHERE NOT granted;
```

**Solutions**:
1. Check for long-running transactions blocking writes
2. Verify no table-level locks (DDL operations during writes)
3. Consider increasing `max_locks_per_transaction` if hitting limit

## Benchmarks

These are reference benchmarks from testing multi-app support:

### Write Performance

| Scenario | Throughput | P95 Latency | P99 Latency |
|----------|------------|-------------|-------------|
| 1 app, sequential | 200 writes/sec | 5ms | 10ms |
| 5 apps, sequential | 195 writes/sec | 6ms | 12ms |
| 5 apps, 10 threads | 950 writes/sec | 25ms | 45ms |
| 5 apps, 50 threads | 2800 writes/sec | 85ms | 150ms |

*Test environment: PostgreSQL 14, 4 CPU, 8GB RAM, local network*

### Cache Performance

| Operation | Without Cache | With Cache | Speedup |
|-----------|---------------|------------|---------|
| Application lookup | 2.5ms | 0.05ms | 50x |
| 1000 lookups | 2500ms | 50ms | 50x |

### Query Performance

| Query | All Apps | Single App | Reduction |
|-------|----------|------------|-----------|
| Dashboard stats | 45ms | 12ms | 73% |
| Analytics (7 days) | 180ms | 55ms | 69% |
| Error list (paginated) | 25ms | 8ms | 68% |

*Based on database with 100,000 errors across 5 applications*

## Optimization Tips

1. **Use Async Logging**: Enable `config.async_logging = true` to move error writes out of request cycle

2. **Archive Old Errors**: Schedule `RailsErrorDashboard::RetentionCleanupJob` (see [Schedule the periodic jobs](/rails_error_dashboard/docs/production/#2-schedule-the-periodic-jobs)), or run the `error_dashboard:cleanup_resolved` rake task by hand to remove old resolved errors (it asks for confirmation)

3. **Separate Database**: Consider dedicated database for error dashboard to isolate performance impact

4. **Connection Pooling**: Increase connection pool size if seeing "could not obtain connection" errors

5. **Sampling**: Enable error sampling for high-frequency errors to reduce write volume

## Contact

For performance issues or optimization questions:
- GitHub Issues: https://github.com/AnjanJ/rails_error_dashboard/issues
- Performance label: `performance` + `multi-app`

Include:
- Database type and version
- Number of applications
- Error write rate (per second)
- Relevant query plans (`EXPLAIN ANALYZE` output)
- APM screenshots if available
