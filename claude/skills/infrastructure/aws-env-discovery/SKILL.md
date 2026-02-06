---
name: aws-env-discovery
description: Discover AWS resources (RDS instances, databases, secrets) across environments. Use when needing to find database connection details, list available databases, retrieve credentials from Secrets Manager, or set up database tool configurations. Triggers on phrases like "what databases are in QA", "get UAT credentials", "list RDS instances", "database connection info", or "set up database connections".
---

# AWS Environment Discovery

Discover RDS instances, databases, and credentials across AWS environments (QA, UAT, Production).

## Quick Reference

| Environment | Profile      | Typical Use                        |
| ----------- | ------------ | ---------------------------------- |
| QA          | `qa`         | Testing, development               |
| UAT         | `uat`        | User acceptance testing            |
| Production  | `production` | Live systems (read-only discovery) |

## Workflow

### 1. Authenticate to Environment

Check if already authenticated:

```bash
aws sts get-caller-identity --profile <env>
```

If expired or not authenticated:

```bash
aws sso login --profile <env>
```

### 2. Discover RDS Instances

List all RDS instances in the environment:

```bash
aws rds describe-db-instances --profile <env> \
  --query 'DBInstances[*].[DBInstanceIdentifier,Engine,Endpoint.Address,Endpoint.Port,DBInstanceStatus]' \
  --output table
```

### 3. List Databases on an Instance

For PostgreSQL instances, connect and list databases:

```bash
psql -h <endpoint> -U <username> -d postgres -c "\l"
```

Or via AWS if using IAM auth:

```bash
aws rds describe-db-instances --profile <env> \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0]'
```

### 4. Retrieve Credentials from Secrets Manager

List available secrets:

```bash
aws secretsmanager list-secrets --profile <env> \
  --query 'SecretList[*].[Name,Description]' \
  --output table
```

Get specific secret value:

```bash
aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> \
  --query 'SecretString' \
  --output text | jq .
```

## Output Format

Present discoveries as markdown tables:

### RDS Instances

| Instance | Engine   | Endpoint                       | Port | Status    |
| -------- | -------- | ------------------------------ | ---- | --------- |
| myapp-qa | postgres | myapp-qa.xxx.rds.amazonaws.com | 5432 | available |

### Credentials Retrieved

| Secret Name | Username | Database | Notes                          |
| ----------- | -------- | -------- | ------------------------------ |
| myapp/qa/db | app_user | myapp    | Retrieved from Secrets Manager |

### Connection Strings

```
postgresql://username:password@endpoint:port/database
```

## SSO Re-authentication

When commands fail with credential errors:

1. Detect the error pattern: "Token has expired" or "credentials have expired"
2. Prompt user: "SSO session expired for [env]. Run `aws sso login --profile [env]`?"
3. After login, retry the failed command

## Safety Notes

- Production discovery is read-only (describe/list commands only)
- Never output raw passwords in conversation - use `****` redaction
- Prefer connection string format over separate credential display
- Always confirm environment before running commands
