# EventStore Investigation Queries

## Subscription Lag

### All subscriptions with lag

```sql
SELECT
  subscription_name,
  last_seen_event_number,
  (SELECT max(event_number) FROM events) AS latest_event,
  (SELECT max(event_number) FROM events) - last_seen_event_number AS lag
FROM subscriptions
ORDER BY lag DESC;
```

### Subscription position history (check if progressing)

```sql
-- Run this query twice, 30 seconds apart
-- If last_seen_event_number doesn't change, subscription is stuck
SELECT subscription_name, last_seen_event_number, now()
FROM subscriptions
WHERE subscription_name = '<subscription_name>';
```

## Dead Subscription Detection

### Subscriptions that haven't moved

```sql
-- Compare current position to a known baseline
-- A subscription with lag > 0 that hasn't moved is likely stuck
SELECT
  subscription_name,
  last_seen_event_number,
  (SELECT max(event_number) FROM events) - last_seen_event_number AS lag
FROM subscriptions
WHERE (SELECT max(event_number) FROM events) - last_seen_event_number > 1000
ORDER BY lag DESC;
```

## Event Stream Inspection

### Events for a specific aggregate

```sql
SELECT
  event_number,
  stream_uuid,
  stream_version,
  event_type,
  created_at,
  data::text
FROM events
WHERE stream_uuid = '<aggregate_id>'
ORDER BY stream_version;
```

### Recent events by type

```sql
SELECT
  event_number,
  stream_uuid,
  event_type,
  created_at
FROM events
WHERE event_type = '<EventType>'
ORDER BY event_number DESC
LIMIT 20;
```

### Events in a time range

```sql
SELECT
  event_number,
  stream_uuid,
  event_type,
  created_at
FROM events
WHERE created_at BETWEEN '<start_time>' AND '<end_time>'
ORDER BY event_number;
```

### Event count by type (recent)

```sql
SELECT
  event_type,
  count(*) AS event_count,
  max(created_at) AS latest
FROM events
WHERE created_at > now() - interval '1 hour'
GROUP BY event_type
ORDER BY event_count DESC;
```

## Stream Analysis

### Total event count

```sql
SELECT max(event_number) AS total_events FROM events;
```

### Events per stream (top streams by volume)

```sql
SELECT
  stream_uuid,
  count(*) AS event_count,
  max(stream_version) AS latest_version
FROM events
GROUP BY stream_uuid
ORDER BY event_count DESC
LIMIT 20;
```

### Stream version for a specific aggregate

```sql
SELECT max(stream_version) AS current_version
FROM events
WHERE stream_uuid = '<aggregate_id>';
```

## Snapshot Analysis

### Snapshot freshness

```sql
SELECT
  source_uuid,
  source_type,
  source_version,
  created_at
FROM snapshots
ORDER BY created_at DESC
LIMIT 20;
```

## Performance Queries

### Event write rate (last hour, by minute)

```sql
SELECT
  date_trunc('minute', created_at) AS minute,
  count(*) AS events_written
FROM events
WHERE created_at > now() - interval '1 hour'
GROUP BY minute
ORDER BY minute;
```
