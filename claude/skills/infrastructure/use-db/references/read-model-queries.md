# Read Model Investigation Queries

## Oban Job Inspection

### Job summary by queue and state

```sql
SELECT queue, state, count(*)
FROM oban_jobs
GROUP BY queue, state
ORDER BY queue, state;
```

### Pending jobs by queue

```sql
SELECT queue, count(*) AS pending
FROM oban_jobs
WHERE state = 'available'
GROUP BY queue
ORDER BY pending DESC;
```

### Currently executing jobs

```sql
SELECT id, queue, worker, args, attempted_at, attempt
FROM oban_jobs
WHERE state = 'executing'
ORDER BY attempted_at;
```

### Failed/discarded jobs (recent)

```sql
SELECT id, queue, worker, state,
       errors[array_upper(errors, 1)]->>'error' AS last_error,
       attempted_at, attempt, max_attempts
FROM oban_jobs
WHERE state IN ('retryable', 'discarded')
ORDER BY attempted_at DESC
LIMIT 20;
```

### Failed jobs by worker (pattern detection)

```sql
SELECT worker,
       count(*) AS failures,
       min(attempted_at) AS first_failure,
       max(attempted_at) AS last_failure
FROM oban_jobs
WHERE state IN ('retryable', 'discarded')
  AND attempted_at > now() - interval '24 hours'
GROUP BY worker
ORDER BY failures DESC;
```

### Jobs stuck executing (potential zombies)

```sql
SELECT id, queue, worker, args, attempted_at,
       now() - attempted_at AS running_for
FROM oban_jobs
WHERE state = 'executing'
  AND attempted_at < now() - interval '30 minutes'
ORDER BY attempted_at;
```

### Scheduled jobs (future)

```sql
SELECT queue, worker, scheduled_at, count(*)
FROM oban_jobs
WHERE state = 'scheduled'
GROUP BY queue, worker, scheduled_at
ORDER BY scheduled_at
LIMIT 20;
```

## Projection Freshness

### Recently updated projections

```sql
-- Replace <projection_table> with actual table name
SELECT id, updated_at
FROM <projection_table>
ORDER BY updated_at DESC
LIMIT 10;
```

## Entity Lookups

```sql
-- Adapt table names to your schema
SELECT * FROM <table_name> WHERE id = '<entity_id>';
```

## Connection Pool Status

### Active connections (from pg_stat_activity)

```sql
SELECT
  datname,
  usename,
  application_name,
  state,
  count(*) AS connections
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY datname, usename, application_name, state
ORDER BY connections DESC;
```

### Connection limits

```sql
SHOW max_connections;

SELECT count(*) AS active_connections
FROM pg_stat_activity
WHERE datname = current_database();
```

### Long-running queries

```sql
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  state,
  query
FROM pg_stat_activity
WHERE datname = current_database()
  AND state != 'idle'
  AND pg_stat_activity.query_start < now() - interval '30 seconds'
ORDER BY duration DESC;
```

## Table Sizes

### Largest tables

```sql
SELECT
  schemaname || '.' || tablename AS table,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS data_size,
  pg_size_pretty(pg_indexes_size(schemaname || '.' || tablename::regclass)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 20;
```
