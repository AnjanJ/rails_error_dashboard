---
layout: default
title: "Database Optimization Guide"
order: 3
---

# Database Optimization Guide

This guide explains the database optimizations in RailsErrorDashboard and how to get the best performance.

## Index Strategy

RailsErrorDashboard uses a comprehensive indexing strategy to ensure fast queries even with millions of error records.

### Single-Column Indexes

These indexes support basic filtering and sorting:

```ruby
# From initial migration
add_index :error_logs, :user_id
add_index :error_logs, :error_type
add_index :error_logs, :resolved
add_index :error_logs, :occurred_at
add_index :error_logs, :platform
add_index :error_logs, :error_hash
add_index :error_logs, :first_seen_at
add_index :error_logs, :last_seen_at
add_index :error_logs, :occurrence_count
```

### Composite Indexes

These indexes optimize common query patterns that filter + sort:

#### 1. **Resolved + Occurred At**
```ruby
add_index :error_logs, [:resolved, :occurred_at]
```

**Use case:** Dashboard stats showing unresolved errors from last 7/30 days
```ruby
# Query optimized by this index:
ErrorLog.where(resolved: false).where("occurred_at >= ?", 7.days.ago).count
```

**Performance gain:** 100x faster on large datasets

---

#### 2. **Error Type + Occurred At**
```ruby
add_index :error_logs, [:error_type, :occurred_at]
```

**Use case:** Filtering by specific error type with time ordering
```ruby
# Query optimized by this index:
ErrorLog.where(error_type: "NoMethodError").order(occurred_at: :desc)
```

**Performance gain:** 50-100x faster on large datasets

---

#### 3. **Platform + Occurred At**
```ruby
add_index :error_logs, [:platform, :occurred_at]
```

**Use case:** Mobile error dashboards filtering by iOS/Android
```ruby
# Query optimized by this index:
ErrorLog.where(platform: "iOS").order(occurred_at: :desc)
```

**Performance gain:** 50-100x faster on large datasets

---

#### 4. **Error Hash + Resolved + Occurred At** (CRITICAL)
```ruby
add_index :error_logs, [:error_hash, :resolved, :occurred_at]
```

**Use case:** Error deduplication (happens on EVERY error log)
```ruby
# Query optimized by this index (runs on every error). Simplified: the real
# lookup also filters by application and environment and skips "Won't fix" errors.
ErrorLog
  .where(error_hash: hash)
  .where(resolved: false)
  .where("occurred_at >= ?", 24.hours.ago)
  .first
```

On PostgreSQL and SQLite, a unique index on the error group (`index_error_logs_on_group_identity`)
also stops two processes from creating the same error twice.

**Performance gain:** 1000x faster - this is the hot path
**Impact:** Without this index, error logging slows down linearly with DB size

---

### PostgreSQL-Specific Optimizations

If you're using PostgreSQL (recommended for production), you get additional optimizations:

#### 1. **Partial Index for Unresolved Errors**
```ruby
add_index :error_logs, :occurred_at, where: "resolved = false"
```

**Why partial?** Only indexes unresolved errors
- **Smaller index** = faster queries
- **Less maintenance** = faster writes
- **Better caching** = more fits in memory

**Use case:** Most dashboard queries filter by `resolved = false`

---

#### 2. **GIN Full-Text Search Index**
```sql
CREATE INDEX index_error_logs_on_searchable_text
ON rails_error_dashboard_error_logs
USING gin(to_tsvector('english',
  COALESCE(message, '') || ' ' || COALESCE(backtrace, '') || ' ' || COALESCE(error_type, '')
))
```

**What is GIN?** Generalized Inverted Index for full-text search
- **Case-insensitive** by default
- **Handles word stemming** (searching "fail" finds "failed", "failing")

**Use case:** the dashboard's search box. On PostgreSQL it matches against
message, backtrace and error type together, and PostgreSQL uses an expression
index only when the query's expression is identical to the index's — which is
why the index covers exactly that concatenation and nothing else.
```ruby
# Uses index_error_logs_on_searchable_text on PostgreSQL:
RailsErrorDashboard::Queries::ErrorsList.call(search: "payment failed")
```

**Measured** (PostgreSQL 16, 200,000 error logs, a term present in one row,
searching all errors): 992 ms without the index, 0.012 ms with it. A common
term looks fast either way because the query stops at the first page of hits.

**Upgrading:** installs created from the squashed migration before 0.11.8 had
no usable search index (0.11.7 added one on `message` alone, which the search
never matches). [Upgrade](/rails_error_dashboard/docs/upgrading/#the-upgrade) to 0.11.8 or later to
get `index_error_logs_on_searchable_text`; the migration also drops the
unused `message`-only index.

---

## Query Optimization Examples

### Before Optimization
```ruby
# Slow: Full table scan
ErrorLog.where(error_type: "NoMethodError").order(occurred_at: :desc).limit(50)
# Execution time: 1500ms on 1M records
```

### After Optimization
```ruby
# Fast: Uses composite index on (error_type, occurred_at)
ErrorLog.where(error_type: "NoMethodError").order(occurred_at: :desc).limit(50)
# Execution time: 5ms on 1M records
```

---

## Index Maintenance

### Monitoring Index Usage

**PostgreSQL:**
```sql
-- Check index usage
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan as index_scans,
  idx_tup_read as tuples_read
FROM pg_stat_user_indexes
WHERE tablename = 'rails_error_dashboard_error_logs'
ORDER BY idx_scan DESC;
```

**MySQL:**
```sql
-- Check index cardinality
SHOW INDEX FROM rails_error_dashboard_error_logs;
```

### Rebuilding Indexes (PostgreSQL)

If indexes become bloated over time:

```sql
-- Rebuild all indexes (requires EXCLUSIVE lock)
REINDEX TABLE rails_error_dashboard_error_logs;

-- Or rebuild concurrently (PostgreSQL 12+, no lock)
REINDEX TABLE CONCURRENTLY rails_error_dashboard_error_logs;
```

### Analyzing Tables

Help the query planner make better decisions:

```sql
-- PostgreSQL
ANALYZE rails_error_dashboard_error_logs;

-- MySQL
ANALYZE TABLE rails_error_dashboard_error_logs;
```

---

## Database-Specific Recommendations

### PostgreSQL (Recommended)

**Best for:**
- Production applications
- High-volume error logging
- Full-text search requirements

**Configuration:**
```ruby
# config/database.yml
production:
  adapter: postgresql
  pool: 25  # Set based on concurrency needs
  timeout: 5000

  # PostgreSQL-specific optimizations
  variables:
    work_mem: '16MB'  # For sorting/hashing
    maintenance_work_mem: '256MB'  # For index creation
    effective_cache_size: '4GB'  # Help query planner
```

**Index sizes (approximate):**
- 1M records: ~500MB total indexes
- 10M records: ~5GB total indexes

---

### MySQL

**Good for:**
- Moderate-volume applications
- Shared hosting environments
- Simpler deployments

**Limitations:**
- No partial indexes (indexes are larger)
- No GIN or FULLTEXT index: the search box uses `LIKE`, which scans the table

**Configuration:**
```ruby
# config/database.yml
production:
  adapter: trilogy  # or mysql2
  pool: 25

  # Session variables, in bytes. Rails sets these with SET @@SESSION, so
  # server-wide settings such as innodb_buffer_pool_size belong in my.cnf.
  variables:
    sort_buffer_size: 2097152
    read_buffer_size: 2097152
```

---

### SQLite

**Good for:**
- Development/testing
- Small applications (<100K errors)
- Embedded deployments

**Limitations:**
- No partial indexes
- No GIN indexes: the search box uses `LIKE`
- Limited concurrency
- Not recommended for production high-volume apps

**Configuration:**
```ruby
# config/database.yml
development:
  adapter: sqlite3
  timeout: 5000

  # SQLite pragmas for better performance
  pragmas:
    journal_mode: :wal
    synchronous: :normal
    cache_size: 10000
```

---

## Performance Benchmarks

Test environment: PostgreSQL 14, 1M error records

### Dashboard Stats Query
```ruby
ErrorLog.where(resolved: false).where("occurred_at >= ?", 7.days.ago).count
```

| Index Strategy | Execution Time | Speedup |
|---------------|----------------|---------|
| No indexes    | 2500ms         | 1x      |
| Single index on `resolved` | 1200ms | 2x |
| Single index on `occurred_at` | 800ms | 3x |
| **Composite index (resolved, occurred_at)** | **15ms** | **166x** |

### Error List Query
```ruby
ErrorLog.where(error_type: "NoMethodError").order(occurred_at: :desc).limit(50)
```

| Index Strategy | Execution Time | Speedup |
|---------------|----------------|---------|
| No indexes    | 3000ms         | 1x      |
| Single index on `error_type` | 800ms | 3.7x |
| Single index on `occurred_at` | 1500ms | 2x |
| **Composite index (error_type, occurred_at)** | **8ms** | **375x** |

### Deduplication Lookup (Hot Path)
```ruby
# Simplified, as above
ErrorLog.where(error_hash: hash, resolved: false).where("occurred_at >= ?", 24.hours.ago).first
```

| Index Strategy | Execution Time | Speedup |
|---------------|----------------|---------|
| No indexes    | 5000ms         | 1x      |
| Single index on `error_hash` | 50ms | 100x |
| Composite index (error_hash, resolved) | 10ms | 500x |
| **Composite index (error_hash, resolved, occurred_at)** | **2ms** | **2500x** |

### Full-Text Search
```ruby
ErrorLog.where("message LIKE ?", "%payment%")  # vs GIN index
```

| Database | Strategy | Execution Time | Speedup |
|----------|----------|----------------|---------|
| PostgreSQL | LIKE query | 4000ms | 1x |
| PostgreSQL | **GIN index** | **8ms** | **500x** |
| SQLite | LIKE query | 6000ms | 1x |

MySQL also uses a `LIKE` query: RED creates no FULLTEXT index.

---

## Migration Guide

Nothing runs automatically. New indexes arrive as migrations with each release: run
[the upgrade](/rails_error_dashboard/docs/upgrading/#the-upgrade), which copies them into your app, then
`bin/rails db:migrate`. With a separate error database, don't use
`rails_error_dashboard:install:migrations`: it copies the migrations into `db/migrate/`, and
`db:migrate` then builds RED's tables in your main database.

### Checking Migration Status

```bash
# RED's migrations (the name shows as "... rails error dashboard")
bin/rails db:migrate:status | grep -i 'rails error dashboard'

# With a separate error database
bin/rails db:migrate:status:error_dashboard
```

The installer gives each migration a new version number when it copies it into your app, so use
the version this command shows for your app, not one from the gem's source.

### Large Tables

Every index the migrations need already exists after a normal install, so don't add RED's indexes
by hand. On a large table, a release that adds an index can lock the table while it builds. Read
the new migration files before you deploy, and run the migration when traffic is low.

---

## Troubleshooting

### Query Still Slow?

1. **Check index usage:**
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM rails_error_dashboard_error_logs
   WHERE error_type = 'NoMethodError'
   ORDER BY occurred_at DESC
   LIMIT 50;
   ```

2. **Look for "Seq Scan"** in output (bad - not using index)
3. **Look for "Index Scan"** in output (good - using index)

### Index Not Being Used?

Possible causes:
1. **Table too small** - Indexes only help with 10K+ records
2. **Statistics out of date** - Run `ANALYZE table_name`
3. **Wrong query pattern** - Check if your WHERE matches the index columns
4. **Incompatible types** - Ensure column types match in queries

### Out of Disk Space?

Indexes consume disk space (typically 30-50% of table size):

```sql
-- Check index sizes (PostgreSQL)
SELECT
  indexname,
  pg_size_pretty(pg_relation_size(indexname::regclass)) as size
FROM pg_indexes
WHERE tablename = 'rails_error_dashboard_error_logs';
```

**Solution:** Drop unused indexes or increase disk space

---

## Best Practices

1. **Always use composite indexes** for queries with WHERE + ORDER BY
2. **Put high-selectivity columns first** in composite indexes
3. **Use partial indexes** (PostgreSQL) for filtered queries
4. **Monitor index usage** and remove unused indexes
5. **Run ANALYZE** after bulk imports
6. **Use connection pooling** with proper size based on concurrency

---

## Additional Resources

- [PostgreSQL Indexing Best Practices](https://www.postgresql.org/docs/current/indexes.html)
- [MySQL Index Optimization](https://dev.mysql.com/doc/refman/8.0/en/optimization-indexes.html)
- [Rails Indexing Guide](https://guides.rubyonrails.org/active_record_migrations.html#creating-indexes)
