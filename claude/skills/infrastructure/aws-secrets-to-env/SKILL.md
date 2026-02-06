---
name: aws-secrets-to-env
description: Convert AWS Secrets Manager entries to local development formats (.env files, connection strings, JSON). Use when needing to create .env files from AWS secrets, generate connection strings for local development, or export credentials. Triggers on phrases like "create .env from QA secrets", "get connection string for", "export secrets as env vars", "local dev setup from AWS", or "secrets to dotenv".
---

# AWS Secrets to Env

Convert AWS Secrets Manager entries into local development formats.

## Output Formats

| Format            | Use Case                         |
| ----------------- | -------------------------------- |
| `.env`            | Docker, Node.js, most frameworks |
| Connection string | Database tools, ORMs             |
| JSON              | Application configs              |
| Shell export      | Terminal sessions                |

## Workflow

### 1. Authenticate to Environment

```bash
aws sts get-caller-identity --profile <env>
# If expired: aws sso login --profile <env>
```

### 2. List Available Secrets

```bash
aws secretsmanager list-secrets --profile <env> \
  --query 'SecretList[*].[Name]' --output table
```

### 3. Fetch Secret Value

```bash
aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> \
  --query 'SecretString' --output text | jq .
```

### 4. Convert to Requested Format

## Format Examples

### .env Format

Input (from Secrets Manager):

```json
{
  "username": "app_user",
  "password": "secret123",
  "host": "db.example.com",
  "port": "5432",
  "dbname": "myapp"
}
```

Output (.env):

```bash
DB_USERNAME=app_user
DB_PASSWORD=secret123
DB_HOST=db.example.com
DB_PORT=5432
DB_NAME=myapp
```

Conversion command:

```bash
aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> \
  --query 'SecretString' --output text | \
  jq -r 'to_entries | .[] | "DB_\(.key | ascii_upcase)=\(.value)"'
```

### Connection String Format

**PostgreSQL:**

```
postgresql://app_user:secret123@db.example.com:5432/myapp
```

Conversion:

```bash
SECRET=$(aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> --query 'SecretString' --output text)

echo "postgresql://$(echo $SECRET | jq -r '.username'):$(echo $SECRET | jq -r '.password')@$(echo $SECRET | jq -r '.host'):$(echo $SECRET | jq -r '.port')/$(echo $SECRET | jq -r '.dbname')"
```

**MySQL:**

```
mysql://app_user:secret123@db.example.com:3306/myapp
```

### Shell Export Format

```bash
export DB_USERNAME="app_user"
export DB_PASSWORD="secret123"
export DB_HOST="db.example.com"
```

Conversion:

```bash
aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> \
  --query 'SecretString' --output text | \
  jq -r 'to_entries | .[] | "export DB_\(.key | ascii_upcase)=\"\(.value)\""'
```

### JSON Format

For configs that expect JSON:

```bash
aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> \
  --query 'SecretString' --output text | jq .
```

## Common Patterns

### Multiple Secrets to Single .env

```bash
# Combine database and API secrets
{
  aws secretsmanager get-secret-value --profile qa \
    --secret-id db-credentials --query 'SecretString' --output text | \
    jq -r 'to_entries | .[] | "DB_\(.key | ascii_upcase)=\(.value)"'

  aws secretsmanager get-secret-value --profile qa \
    --secret-id api-keys --query 'SecretString' --output text | \
    jq -r 'to_entries | .[] | "API_\(.key | ascii_upcase)=\(.value)"'
} > .env.local
```

### Prefix Customization

Add custom prefix instead of default:

```bash
PREFIX="MYAPP"
aws secretsmanager get-secret-value --profile <env> \
  --secret-id <secret-name> \
  --query 'SecretString' --output text | \
  jq -r --arg p "$PREFIX" 'to_entries | .[] | "\($p)_\(.key | ascii_upcase)=\(.value)"'
```

## Safety Notes

- Never commit generated .env files (add to .gitignore)
- Use `.env.local` or `.env.development` for local overrides
- Prefer writing to stdout, prompt before writing to file
- Warn if target file already exists
- Redact passwords in conversation output with `****`

## Integration

Works well with:

- `aws-env-discovery` - Find which secrets exist
- `database-inventory` - Know which databases need credentials
