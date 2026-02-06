---
name: ecto-expert
description: Ecto database patterns including schemas, changesets, query composition, Multi transactions, migrations, and performance
---

# Ecto Expert

## Decision Tree: Query Approach

```
What data operation?
├── Fetch by primary key? → Repo.get / Repo.get!
├── Fetch by unique field? → Repo.get_by / Repo.get_by!
├── Filtered list? → Composable query functions |> Repo.all()
├── Complex joins/aggregates? → from() + join + select
├── Exists check? → Repo.exists?(query)
├── Count? → Repo.aggregate(query, :count)
├── Multiple related writes? → Ecto.Multi
├── Upsert? → Repo.insert(changeset, on_conflict: ...)
├── Bulk insert? → Repo.insert_all (bypasses changesets)
└── Streaming large results? → Repo.stream (inside transaction)
```

## Decision Tree: Changeset Strategy

```
What validation?
├── Standard field validation? → cast + validate_required + validate_format
├── Cross-field validation? → validate_change/3 or custom function
├── Database constraint? → unique_constraint / check_constraint (AFTER insert)
├── Association management? → cast_assoc / put_assoc
├── Different rules per action? → separate changeset functions
│   ├── create_changeset/2 — stricter, all fields required
│   └── update_changeset/2 — partial updates allowed
├── No schema? → Schemaless changeset ({types_map, %{}})
└── Embedded data? → embedded_schema + cast_embed
```

## Schema Patterns

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :member, :viewer]
    field :password_hash, :string, redact: true

    # Virtual fields — not persisted
    field :password, :string, virtual: true, redact: true

    # Associations
    belongs_to :organization, MyApp.Accounts.Organization
    has_many :posts, MyApp.Content.Post
    many_to_many :teams, MyApp.Accounts.Team, join_through: "users_teams"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role, :password])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:password, min: 8)
    |> unique_constraint(:email)
    |> hash_password()
  end

  defp hash_password(%{valid?: true, changes: %{password: pw}} = cs) do
    put_change(cs, :password_hash, Bcrypt.hash_pwd_salt(pw))
  end
  defp hash_password(cs), do: cs
end
```

## Query Composition

```elixir
defmodule MyApp.Accounts.UserQuery do
  import Ecto.Query

  def base, do: from(u in User, as: :user)
  def active(query), do: where(query, [user: u], u.active == true)
  def by_role(query, role), do: where(query, [user: u], u.role == ^role)
  def by_org(query, org_id), do: where(query, [user: u], u.organization_id == ^org_id)
  def with_posts(query), do: preload(query, [:posts])
  def ordered(query), do: order_by(query, [user: u], desc: u.inserted_at)
  def limit_to(query, n), do: limit(query, ^n)
end

# Usage — compose as pipeline
UserQuery.base()
|> UserQuery.active()
|> UserQuery.by_role(:admin)
|> UserQuery.ordered()
|> Repo.all()
```

## Ecto.Multi (Transactions)

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
|> Ecto.Multi.run(:profile, fn repo, %{user: user} ->
  # Arbitrary logic inside transaction
  repo.insert(Profile.changeset(%Profile{user_id: user.id}, profile_attrs))
end)
|> Ecto.Multi.update(:org, fn %{user: user} ->
  Organization.increment_members_changeset(org, user)
end)
|> Repo.transaction()
|> case do
  {:ok, %{user: user, profile: profile}} -> {:ok, user}
  {:error, failed_op, changeset, _changes} -> {:error, {failed_op, changeset}}
end
```

## Preload Strategies

```
Which preload?
├── Always need association? → preload in query (join + preload)
├── Conditional need? → Repo.preload after fetch
├── N+1 in list? → preload in query (always)
├── Nested associations? → preload([:posts, comments: :author])
└── GraphQL/Dataloader? → Dataloader (batch by default)

# In-query preload (single query with join)
from(u in User, join: p in assoc(u, :posts), preload: [posts: p])

# Separate query preload (2 queries, simpler)
from(u in User, preload: [:posts])
```

## Migration Patterns

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :organization_id, references(:organizations, type: :binary_id), null: false
      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:organization_id])
  end
end
```

**Safe migration rules:**

- Add columns as nullable first, backfill, then add NOT NULL
- Add indexes concurrently: `create index(:users, [:email], concurrently: true)` (requires `@disable_ddl_transaction true`)
- Never rename columns in a single deploy — add new, migrate data, remove old

## Performance Patterns

```elixir
# Batch inserts (bypasses changesets — use for seeds/imports)
Repo.insert_all(User, users_list, on_conflict: :nothing)

# Stream for large datasets (must be in transaction)
Repo.transaction(fn ->
  User
  |> where([u], u.active == true)
  |> Repo.stream(max_rows: 500)
  |> Stream.each(&process/1)
  |> Stream.run()
end)

# Avoid N+1 — ALWAYS preload in list queries
# BAD:  users |> Enum.map(& &1.posts)  # N+1 if not preloaded
# GOOD: from(u in User, preload: [:posts]) |> Repo.all()
```

## References

- `references/queries-advanced.md` — Window functions, CTEs, lateral joins, dynamic queries
- `references/migrations.md` — Zero-downtime migrations, rollback patterns, data migrations
