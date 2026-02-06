---
name: database-inventory
description: Maintain documentation of databases across AWS environments. Use when needing to update database lists, compare environments, track new or removed databases, or generate database documentation. Triggers on phrases like "update database inventory", "what databases were added", "sync database docs", "compare QA and UAT databases", or "document our databases".
---

# Database Inventory

Maintain and update documentation of databases across AWS environments (QA, UAT, Production).

## Inventory Location

Default inventory file: `.stoobz/datagrip/databases.md`

## Workflow

### 1. Load Current Inventory

Read the existing inventory file to understand documented state:

```bash
cat .stoobz/datagrip/databases.md
```

### 2. Fetch Live Database List

For each environment, get current databases:

```bash
# Get RDS endpoint
ENDPOINT=$(aws rds describe-db-instances --profile <env> \
  --query 'DBInstances[0].Endpoint.Address' --output text)

# Get credentials from Secrets Manager
CREDS=$(aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> --query 'SecretString' --output text)

# List databases (PostgreSQL)
PGPASSWORD=$(echo $CREDS | jq -r .password) psql \
  -h $ENDPOINT \
  -U $(echo $CREDS | jq -r .username) \
  -d postgres \
  -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" \
  -t
```

### 3. Compare and Report

Generate comparison between documented and live state:

| Status     | Database     | Environment | Notes                    |
| ---------- | ------------ | ----------- | ------------------------ |
| ✅ Exists  | orders_db    | QA          | Documented and present   |
| ➕ New     | analytics_db | QA          | Not in inventory         |
| ❌ Removed | legacy_db    | QA          | In inventory but missing |

### 4. Update Inventory

Update the markdown file with:

- Current database list per environment
- Last updated timestamp
- Any notes about changes

## Inventory Format

```markdown
# Database Inventory

Last updated: 2026-02-02

## QA Environment

| Database  | Purpose          | Owner       | Notes        |
| --------- | ---------------- | ----------- | ------------ |
| orders_db | Order processing | orders-team | Primary OLTP |
| users_db  | User accounts    | auth-team   |              |

## UAT Environment

| Database  | Purpose          | Owner       | Notes        |
| --------- | ---------------- | ----------- | ------------ |
| orders_db | Order processing | orders-team | Mirror of QA |
```

## Commands

### Full Sync

Fetch all environments and update inventory:

1. Authenticate to each environment
2. List all databases
3. Compare with inventory
4. Report changes
5. Prompt to update file

### Quick Check

Compare single environment without updating:

```bash
# Just show differences, don't modify inventory
```

## Integration with aws-env-discovery

This skill complements `aws-env-discovery`:

- Use `aws-env-discovery` to get connection details
- Use `database-inventory` to maintain documentation

## Safety Notes

- Always show diff before updating inventory file
- Preserve manual annotations (Purpose, Owner, Notes columns)
- Back up inventory before major updates
