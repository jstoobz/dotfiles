# Ecto Migrations Reference

## Safe Migration Patterns

### Adding a Column

```elixir
# Safe: Add as nullable first
def change do
  alter table(:users) do
    add :phone, :string  # nullable by default
  end
end

# Then backfill in a separate migration or task
# Then add NOT NULL in another migration if needed:
def change do
  alter table(:users) do
    modify :phone, :string, null: false, from: {:string, null: true}
  end
end
```

### Adding an Index Concurrently

```elixir
# MUST disable DDL transaction for concurrent index creation
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  create index(:users, [:email], concurrently: true)
end
```

### Renaming (Zero-Downtime)

```elixir
# DON'T: rename in a single deploy (old code still references old name)
# rename table(:users), :name, to: :full_name

# DO: Three-step process across deploys:
# Deploy 1: Add new column, write to both
def change do
  alter table(:users) do
    add :full_name, :string
  end
  # Backfill: UPDATE users SET full_name = name WHERE full_name IS NULL
end

# Deploy 2: Switch reads to new column, keep writing to both
# Deploy 3: Remove old column
def change do
  alter table(:users) do
    remove :name
  end
end
```

## Common Migration Operations

### Create Table

```elixir
def change do
  create table(:policies, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :number, :string, null: false
    add :status, :string, null: false, default: "draft"
    add :effective_date, :date
    add :premium, :decimal, precision: 12, scale: 2
    add :metadata, :map, default: %{}
    add :account_id, references(:accounts, type: :binary_id, on_delete: :restrict), null: false
    timestamps()
  end

  create unique_index(:policies, [:number])
  create index(:policies, [:account_id])
  create index(:policies, [:status])
end
```

### Enum Type (PostgreSQL)

```elixir
# Up/down required — PostgreSQL enums can't be rolled back with change
def up do
  execute "CREATE TYPE policy_status AS ENUM ('draft', 'active', 'expired', 'cancelled')"

  alter table(:policies) do
    add :status_enum, :policy_status
  end
end

def down do
  alter table(:policies) do
    remove :status_enum
  end

  execute "DROP TYPE policy_status"
end
```

### Check Constraint

```elixir
def change do
  create constraint(:invoices, :amount_must_be_positive, check: "amount > 0")
  create constraint(:policies, :dates_valid, check: "end_date > start_date")
end
```

### Partial Index

```elixir
def change do
  # Index only active records — smaller, faster
  create index(:users, [:email], where: "active = true", name: :users_active_email_index)
end
```

## Data Migrations

### In-Migration Data Backfill (Small Tables)

```elixir
def up do
  alter table(:users) do
    add :display_name, :string
  end

  flush()  # Execute pending DDL before data migration

  execute "UPDATE users SET display_name = name WHERE display_name IS NULL"
end
```

### Separate Data Migration Task (Large Tables)

```elixir
# lib/mix/tasks/backfill_display_names.ex
defmodule Mix.Tasks.BackfillDisplayNames do
  use Mix.Task

  def run(_args) do
    Mix.Task.run("app.start")

    MyApp.Repo.transaction(fn ->
      from(u in "users", where: is_nil(u.display_name))
      |> MyApp.Repo.stream(max_rows: 1000)
      |> Stream.each(fn user ->
        MyApp.Repo.update_all(
          from(u in "users", where: u.id == ^user.id),
          set: [display_name: user.name]
        )
      end)
      |> Stream.run()
    end, timeout: :infinity)
  end
end
```

## Rollback Patterns

```elixir
# change/0 auto-generates rollback for most operations
def change do
  create table(:things) do ... end  # rollback: drop table
  add :col, :string                 # rollback: remove :col
  create index(...)                 # rollback: drop index
end

# up/down for non-reversible operations
def up do
  execute "CREATE EXTENSION IF NOT EXISTS citext"
end

def down do
  execute "DROP EXTENSION IF EXISTS citext"
end
```

## Migration Best Practices

1. **One concern per migration** — don't mix schema changes with data migrations
2. **Always test rollback** — `mix ecto.rollback` then `mix ecto.migrate`
3. **Name migrations descriptively** — `create_users`, `add_email_to_users`, `index_users_on_email`
4. **Use `flush/0`** — when you need DDL to complete before DML in the same migration
5. **Avoid referencing app code** — migrations should be self-contained (schemas change over time)
6. **Index foreign keys** — always create an index for `references()` columns
7. **Consider table locks** — `ALTER TABLE` takes an exclusive lock; on large tables, use concurrent operations
