---
name: ecto-expert
description: Ecto database patterns — schemas, changesets, query composition, Multi transactions, migrations, ParameterizedType, UUIDv7, and performance tuning
targets:
  elixir: "1.18+"
  ecto: "3.12+"
  ecto_sql: "3.12+"
  otp: "27+"
---

# Ecto Expert

## When to Use This Skill

- Designing or modifying schemas, embedded schemas, or `ParameterizedType` definitions
- Writing or composing queries, multi-table joins, dynamic where clauses
- Building changesets: validation, association casting, custom validators
- Multi-step transactional operations via `Ecto.Multi`
- Writing migrations (especially zero-downtime patterns) or backfill scripts
- Performance tuning: preloading, `insert_all`, streaming, connection pool sizing
- **Skip this skill when working on test factories or DB sandbox setup (use `elixir-testing-expert`), GraphQL resolvers (use `absinthe-expert`), or Commanded projections at the architectural level (use `commanded-expert` — Ecto patterns inside projections still apply here).**

## Mental Model

- **Schema declares shape; changeset declares change.** Schemas are pure data definitions. Changesets carry the diff between current and desired state PLUS validation results. Every write goes through a changeset; every changeset is the audit trail of "what was attempted and why it (didn't) work."
- **Queries are composable values, not strings.** `from(u in User)` returns a struct. You can pipe it through filter functions, hand it to other modules, store it in a list. Composition over construction.
- **The Repo is the boundary, the only side-effecting layer.** Schemas don't talk to databases; queries don't either. Only `Repo.all`, `Repo.insert`, `Repo.transaction` etc. touch the DB. Keep Repo calls in contexts (see `phoenix-expert`), never in schemas or changesets.
- **Migrations are forward-only in spirit.** Even reversible migrations should treat rollback as a recovery tool, not a development workflow. Plan changes that work in *both* directions during deploy.

## Decision Tree: Query Approach

```
What data operation?
├── Fetch by primary key? → Repo.get / Repo.get!
├── Fetch by unique field? → Repo.get_by / Repo.get_by!
├── Filtered list? → Composable query functions |> Repo.all()
├── Complex joins / aggregates? → from() + join + select
├── Existence check (don't need the row)? → Repo.exists?(query)
├── Count? → Repo.aggregate(query, :count)
├── Multiple related writes (atomic)? → Ecto.Multi
├── Upsert? → Repo.insert(changeset, on_conflict: ...)
├── Bulk insert (no changesets, no callbacks)? → Repo.insert_all
└── Streaming large results? → Repo.stream (inside transaction)
```

## Decision Tree: Changeset Strategy

```
What kind of validation?
├── Standard field validation? → cast + validate_required + validate_format/_length/_inclusion
├── Cross-field validation? → validate_change/3 or a custom function in the pipeline
├── Database constraint enforcement? → unique_constraint / foreign_key_constraint / check_constraint (AFTER the cast)
├── Association management? → cast_assoc / put_assoc
├── Different rules per action? → separate changeset functions
│   ├── create_changeset/2 — strict, all required fields
│   └── update_changeset/2 — partial updates allowed
├── No schema (form-only data)? → Schemaless changeset ({types_map, %{}})
├── Embedded data (struct inside parent)? → embedded_schema + cast_embed
└── Field type isn't fixed at compile time (multi-tenant, plugin)? → Ecto.ParameterizedType
```

## Decision Tree: Preload Strategy

```
How should this association load?
├── Always need it on this query? → preload in the query (single SQL with join, or 2 queries)
├── Conditional / optional? → Repo.preload after fetch
├── Listing rows that all need the assoc (N+1 risk)? → preload in query (always)
├── Nested associations? → preload([:posts, comments: :author])
├── Need to filter the preloaded rows? → preload(query: from p in Post, where: p.published)
└── GraphQL/Dataloader context? → Dataloader (see absinthe-expert) — never inline preloads in resolvers
```

## Decision Tree: ID Strategy

```
What kind of primary key?
├── Default integer auto-increment? → Default (no @primary_key needed)
├── Distributed system, want to generate IDs in the app? → :binary_id (UUID v4)
├── Need IDs that sort by creation time? → UUIDv7 (Postgres 17+ via uuidv7() OR ecto_uuidv7 lib)
├── Composite key? → @primary_key false + multiple field/3 with primary_key: true
├── External ID from another system? → use that as a non-primary unique field, keep your own surrogate key
└── No primary key (read-only views)? → @primary_key false
```

## Core Patterns

### Schema

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias MyApp.Accounts.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :member, :viewer]
    field :password_hash, :string, redact: true

    # Virtual fields — not persisted, available on the struct
    field :password, :string, virtual: true, redact: true

    # Associations
    belongs_to :organization, Organization
    has_many :posts, MyApp.Content.Post
    many_to_many :teams, MyApp.Accounts.Team, join_through: "users_teams"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role, :password])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_length(:password, min: 12)
    |> unique_constraint(:email)
    |> hash_password()
  end

  defp hash_password(%{valid?: true, changes: %{password: pw}} = cs) do
    put_change(cs, :password_hash, Bcrypt.hash_pwd_salt(pw))
  end
  defp hash_password(cs), do: cs
end
```

**Rule:** Changesets must be pure — never call `Repo.*` from inside one. Validation that needs DB lookup belongs in the context layer, before or after the changeset.

### Composable query functions

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

# Compose as a pipeline in the context
UserQuery.base()
|> UserQuery.active()
|> UserQuery.by_role(:admin)
|> UserQuery.ordered()
|> Repo.all()
```

**Rule:** Use named bindings (`as: :user`) so query composition stays readable as joins are added. Without them, `[u, p, c]` positional bindings get fragile.

### `Ecto.Multi` for atomic multi-step writes

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
|> Ecto.Multi.run(:profile, fn repo, %{user: user} ->
  # Arbitrary logic with prior step results in scope
  repo.insert(Profile.changeset(%Profile{user_id: user.id}, profile_attrs))
end)
|> Ecto.Multi.update(:org, fn %{user: user} ->
  Organization.increment_members_changeset(org, user)
end)
|> Repo.transaction()
|> case do
  {:ok, %{user: user, profile: profile}} -> {:ok, user}
  {:error, failed_op, changeset, _changes_so_far} -> {:error, {failed_op, changeset}}
end
```

**Rule:** Reach for `Multi` whenever 2+ writes need to commit together OR the second write depends on the first's primary key. The error shape is `{:error, failed_op, failed_value, changes_so_far}` — `failed_value` is usually a changeset (the common case shown above), but a `Multi.run/3` step can return `{:error, anything}`, so the third element isn't guaranteed to be a changeset. Pattern-match accordingly.

### `Ecto.ParameterizedType` for runtime-shaped fields

```elixir
defmodule MyApp.PrefixedID do
  use Ecto.ParameterizedType

  def type(_params), do: :string
  def init(opts), do: Keyword.fetch!(opts, :prefix)

  def cast(value, prefix) when is_binary(value) do
    if String.starts_with?(value, prefix), do: {:ok, value}, else: :error
  end

  def load(value, _loader, _prefix), do: {:ok, value}
  def dump(value, _dumper, _prefix), do: {:ok, value}
end

# Use in a schema with per-field config
schema "invoices" do
  field :invoice_id, MyApp.PrefixedID, prefix: "inv_"
  field :customer_id, MyApp.PrefixedID, prefix: "cust_"
end
```

**Rule:** `Ecto.ParameterizedType` lets a single type module behave differently per use site (multi-tenant prefixes, configurable formats, plugin-shaped fields). Reach for it when one custom type would otherwise become five near-identical copies.

### Migrations (zero-downtime defaults)

```elixir
defmodule MyApp.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    # Step 1: add nullable column
    alter table(:users) do
      add :role, :string
    end

    # Step 2: backfill in a separate migration (or after deploy), then add constraint
    # alter table(:users), do: modify(:role, :string, null: false)

    # Indexes — concurrent so reads aren't blocked
    create index(:users, [:role], concurrently: true)
  end
end

# When using `concurrently: true` you must disable the migration transaction:
defmodule MyApp.Repo.Migrations.AddIndexConcurrent do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:users, [:email], concurrently: true)
  end
end
```

**Safe migration rules:**

- Add columns nullable first; backfill in a separate deploy; then `null: false` in a third
- Indexes go in their own migration with `concurrently: true` + `@disable_ddl_transaction`
- Never rename columns in a single deploy — add new, dual-write/read, drop old

### `Repo.checkout/2` for explicit connection pinning

```elixir
# Hold one connection across many operations — avoids pool churn for batch work
Repo.checkout(fn ->
  for batch <- Stream.chunk_every(huge_data, 1000) do
    Repo.insert_all(Item, batch)
  end
end)
```

**Rule:** `Repo.checkout/2` reserves a connection from the pool for the duration of the function. Use it for batch operations that would otherwise check out and return the same connection many times. Don't hold the checkout across slow external calls — the pool is shared.

### Performance patterns

```elixir
# Bulk insert — bypasses changesets, no validation, no callbacks
Repo.insert_all(User, users_list, on_conflict: :nothing)

# Stream large datasets — must be inside a transaction
Repo.transaction(fn ->
  User
  |> where([u], u.active == true)
  |> Repo.stream(max_rows: 500)
  |> Stream.each(&process/1)
  |> Stream.run()
end)

# Preload to avoid N+1
# BAD:  users |> Enum.map(& &1.posts)              # N+1 if not preloaded
# GOOD: from(u in User, preload: [:posts]) |> Repo.all()
```

## Anti-patterns

### Don't: call `Repo.*` from inside a changeset

```elixir
# BAD
def changeset(user, attrs) do
  user
  |> cast(attrs, [:email])
  |> validate_email_unique()  # calls Repo.exists?(...)
end

defp validate_email_unique(cs) do
  if Repo.exists?(from u in User, where: u.email == ^get_field(cs, :email)) do
    add_error(cs, :email, "already taken")
  else
    cs
  end
end
```

**Why it bites:** Changesets get built in many contexts — tests, form previews, dry-runs — where DB access isn't available or wanted. Race condition between the check and the insert means you'll get duplicates anyway. Coupling validation to the DB makes changesets non-deterministic.

**Instead:** Use `unique_constraint(:email)` on the changeset and let the database enforce uniqueness via a UNIQUE index. Ecto translates the constraint violation into a changeset error.

### Don't: use `Repo.get!` when missing data is a normal outcome

```elixir
# BAD
def show(conn, %{"id" => id}) do
  user = Repo.get!(User, id)  # raises Ecto.NoResultsError
  render(conn, :show, user: user)
end
```

**Why it bites:** The bang variant is for "missing data is a bug, crash so I see it." A user looking up an ID that doesn't exist is a normal outcome — should render a 404, not crash. The exception turns into a 500 unless you specifically rescue.

**Instead:** Use `Repo.get/2` (returns `nil`) and pattern-match, or build a `fetch_user/1` context function that returns `{:ok, _} | {:error, :not_found}`.

### Don't: write to the database without a changeset

```elixir
# BAD
def update_email(user_id, new_email) do
  Repo.update_all(from(u in User, where: u.id == ^user_id), set: [email: new_email])
end
```

**Why it bites:** `update_all` bypasses changesets entirely. No validation, no constraint translation, no `updated_at` bump (unless you set it manually), no triggers downstream that depend on changeset behavior. Audit trails miss the change. Bad data slips in.

**Instead:** Build a changeset, validate, and `Repo.update`. `update_all` is for legitimate bulk operations (mark all as expired, increment a counter) where validation is provably unnecessary.

### Don't: preload after the fact in a list

```elixir
# BAD — N+1
users = Repo.all(User)
Enum.map(users, fn user ->
  user_with_posts = Repo.preload(user, :posts)  # one query per user
  # ...
end)
```

**Why it bites:** `Repo.preload` on a single struct fires its own SELECT. Doing it inside `Enum.map` means N queries for N users — exactly the N+1 you were trying to avoid by using preload at all.

**Instead:**

```elixir
# GOOD — single batched query for the association
users = Repo.all(from u in User, preload: [:posts])
```

If preload is conditional (only sometimes needed), preload the *list* once after fetching: `Repo.preload(users, :posts)` (note: passing the list, not iterating).

### Don't: bake compile-time secrets into schema field options

```elixir
# BAD
schema "events" do
  field :payload, :map, default: System.get_env("DEFAULT_PAYLOAD")  # compiled in
end
```

**Why it bites:** Schema definitions are evaluated at compile time. `System.get_env` here reads env vars during the build, freezing whatever was set then. The deployed app uses the build-time value, not the runtime one. (See `phoenix-expert` runtime config patterns.)

**Instead:** Use a function default (`default: &my_function/0`) only if the function is pure. For runtime config, set the field in the changeset or context layer where runtime values are accessible.

## Common Gotchas

- **`cast/3` silently drops fields not in the allowed list** — passing `email` when only `[:name]` is allowed produces a changeset where `email` is ignored, no warning. Adding a field requires updating both the schema AND every `cast` call that should accept it.
- **`validate_required` and `unique_constraint` run at different times** — `validate_required` runs at validation; `unique_constraint` only fires AFTER the DB rejects the insert. A changeset can be `valid?: true` and still fail to insert. Always handle the `{:error, changeset}` from `Repo.insert/2`.
- **`has_many` cascade requires a migration-level constraint** — `has_many` in the schema does NOT cascade deletes. You need `references(:users, on_delete: :delete_all)` in the migration, OR `:on_delete` option in `belongs_to` (Ecto-level, slower), OR explicit deletion in a `Multi`.
- **`:binary_id` (UUIDv4) is not sortable** — UUID v4 is random. If you need IDs that sort by creation time (cursor pagination, time-series queries), use UUIDv7 (Postgres 17+ has built-in `uuidv7()`, or use `ecto_uuidv7` for app-level generation).
- **`Repo.preload` doesn't reload** — calling `Repo.preload(user, :posts)` when posts are already loaded is a no-op. To force fresh: `Repo.preload(user, :posts, force: true)`.
- **`Repo.transaction(fn -> ... end)` differs from `Repo.transaction(multi)`** — the function form expects you to return `{:error, _}` or call `Repo.rollback/1` to abort. Multi handles all of this automatically. Prefer Multi for clarity.
- **`embedded_schema` has no `id` by default** — the embedded struct doesn't get a primary key unless you declare one. Useful for value objects (address, money), confusing if you expected a normal schema.
- **`insert_all/3` returns `{count, returning}` not `{:ok, _}`** — without `:returning`, the second element is `nil` (`{count, nil}`). With `returning: [:id, :email]`, it's a list of maps (`{count, [%{id: ..., email: ...}, ...]}`). Treating it as a normal Repo write breaks; always destructure the tuple.
- **Sandbox `:auto` mode requires `async: false`** — `:auto` uses a single shared transaction across the suite, which precludes parallel runs. For `async: true` tests, switch to `:manual` mode and call `Sandbox.checkout/1` in each test's setup. (See `elixir-testing-expert` for the pattern.)
- **Changesets retain the original struct, not the merged data** — `cs.data` is the input struct, `cs.changes` is the diff, `Ecto.Changeset.apply_changes/1` materializes the merged result. Reading `cs.data.email` after a cast won't show the new email.

## Quick Reference

```
Common Repo ops:
  Repo.get(User, id)            # nil if missing
  Repo.get!(User, id)           # raises if missing
  Repo.get_by(User, email: e)
  Repo.all(query)
  Repo.one(query)               # nil or struct (raises if multiple)
  Repo.aggregate(query, :count)
  Repo.exists?(query)
  Repo.insert(changeset)        # {:ok, struct} | {:error, changeset}
  Repo.insert!(changeset)       # raises on error
  Repo.update(changeset)
  Repo.delete(struct_or_changeset)
  Repo.insert_all(schema, list, on_conflict: :nothing)
  Repo.preload(struct_or_list, :assoc)

Query macros (require import Ecto.Query):
  from u in User
  from u in User, where: u.active == true
  from u in User, join: p in assoc(u, :posts), preload: [posts: p]
  from u in User, select: %{id: u.id, name: u.name}
  from u in User, group_by: u.role, select: {u.role, count(u.id)}

Changeset essentials:
  cast(struct, attrs, allowed_fields)
  validate_required([:field])
  validate_length(:field, min: 1, max: 100)
  validate_format(:email, ~r/.../)
  validate_inclusion(:role, [:admin, :member])
  validate_change(:field, fn _, val -> [...] end)
  unique_constraint(:email)
  foreign_key_constraint(:org_id)
  cast_assoc(:profile, with: &Profile.changeset/2)
  put_change(cs, :field, value)
  put_assoc(cs, :tags, [%Tag{...}])
```

## When to Load Deeper References

- Writing window functions, CTEs, lateral joins, dynamic queries, or complex aggregations? → Read `references/queries-advanced.md`
- Planning a zero-downtime migration, large data backfill, or cross-table refactor? → Read `references/migrations.md`
