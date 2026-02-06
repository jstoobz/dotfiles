---
name: use-db
description: Use when needing to query databases across environments (local, QA, UAT, prod) for investigation, debugging, or data verification. Triggers on "check the database", "query eventstore", "subscription lag", "look at UAT", "check QA database", "oban jobs", "read model state", or any database investigation request.
---

# Database Investigation

Query PostgreSQL databases across environments for debugging, investigation, and data verification.

## Arguments

`/use-db <env> <database>`

| Argument     | Values                       | Default                  |
| ------------ | ---------------------------- | ------------------------ |
| `<env>`      | `local`, `qa`, `uat`, `prod` | `local`                  |
| `<database>` | `eventstore`, `app`, `both`  | Infer from investigation |

## Environment Routing

```
Which environment?
├── local → Direct psql connection
│   ├── my_app_dev on localhost:5432
│   └── my_app_eventstore on localhost:5432
├── qa → AWS credentials required
│   ├── Profile: qa
│   └── Compose with /aws-env-discovery for RDS endpoint + secrets
├── uat → AWS credentials required
│   ├── Profile: uat
│   └── Compose with /aws-env-discovery for RDS endpoint + secrets
└── prod → AWS credentials required (READ-ONLY queries only)
    ├── Profile: production
    └── DB queries via psql still possible with credentials
```

## Connection Workflow

### 1. Local Environment

```bash
# App read model
psql -h localhost -p 5432 -U postgres -d my_app_dev

# EventStore
psql -h localhost -p 5432 -U postgres -d my_app_eventstore
```

### 2. Remote Environments (QA/UAT/Prod)

**Step 1: Check/refresh AWS SSO**

```bash
aws sts get-caller-identity --profile <env>
# If expired:
aws sso login --profile <env>
```

**Step 2: Check macOS Keychain for cached credentials**

```bash
# Fast path — check cache first
security find-generic-password -a "<app>-<env>-<db>" -w 2>/dev/null
```

**Step 3: If not cached, discover via AWS**
Compose with `/aws-env-discovery` to find:

- RDS endpoint address and port
- Credentials from Secrets Manager

**Step 4: Connect**

```bash
psql -h <rds-endpoint> -U <username> -d <database>
```

**Step 5: Optionally cache credentials**

```bash
# Ask user before caching
security add-generic-password -a "<app>-<env>-<db>" \
  -s "<app>-db-credentials" \
  -l "<App> <env> <db>" \
  -w "<connection-string>" \
  -U
```

### 3. Production Safety

- Production access is READ-ONLY queries only
- Always add `SET statement_timeout = '30s';` before queries
- Never run UPDATE/DELETE/INSERT on production databases

## Database Routing

```
What are you investigating?
├── Subscription lag → eventstore
├── Event inspection → eventstore
├── Stream analysis → eventstore
├── Dead subscriptions → eventstore
├── Oban jobs → app (read model)
├── Projection freshness → app (read model)
├── Entity lookups → app (read model)
├── Connection pool status → app (read model)
└── Cross-referencing events vs projections → both
```

## Multi-Database Correlation (when `both`)

When using `both`, query both databases to cross-reference:

1. **EventStore**: Get latest events for an aggregate stream
2. **Read Model**: Get current projected state
3. **Compare**: Event stream version vs projection `updated_at` timestamp
4. **Identify gaps**: Missing projections = events processed but projection failed

## Common Investigation Queries

For detailed query references:

- **EventStore queries** → `references/eventstore-queries.md`
- **Read model queries** → `references/read-model-queries.md`

### Quick Reference (most common)

**Subscription lag (EventStore)**:

```sql
SELECT subscription_name,
       last_seen_event_number,
       (SELECT max(event_number) FROM events) - last_seen_event_number AS lag
FROM subscriptions
ORDER BY lag DESC;
```

**Oban job summary (Read Model)**:

```sql
SELECT queue, state, count(*) FROM oban_jobs GROUP BY queue, state ORDER BY queue, state;
```
