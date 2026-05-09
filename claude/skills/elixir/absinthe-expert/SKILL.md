---
name: absinthe-expert
description: Absinthe GraphQL patterns — schema design, resolvers, middleware, Dataloader batching, subscriptions, complexity analysis, and file uploads
targets:
  elixir: "1.18+"
  absinthe: "1.7+"
  dataloader: "2.0+"
  otp: "27+"
---

# Absinthe Expert

## When to Use This Skill

- Designing a GraphQL schema, types, queries, mutations, or input objects
- Writing resolvers, middleware, or Dataloader batch functions
- Implementing GraphQL subscriptions over Phoenix Channels
- Adding query complexity analysis or rate limiting (DoS protection)
- Handling file uploads via the Apollo upload spec
- **Skip this skill when working on REST controllers, JSON APIs without GraphQL, or LiveView-rendered pages — use `phoenix-expert` or `liveview-expert`. Skip for raw Ecto query construction — use `ecto-expert`.**

## Mental Model

- **The schema is the contract.** Clients pick fields; the server resolves only what's asked. Adding a field is non-breaking; renaming or removing one is.
- **Each field resolves independently.** That's the source of GraphQL's flexibility AND its N+1 problem. Without batching, asking for `users { posts { author { name } } }` triggers a query per user, then per post, then per author.
- **Resolvers are the only place for business logic.** Schema definitions are pure structure. Middleware handles cross-cutting concerns (auth, logging). Don't smuggle logic into either.
- **Errors are payload, not HTTP status.** A GraphQL response is almost always `200 OK` with `{ data, errors }`. Field-level errors are normal — partial failure is a feature, not a bug.
- **Subscriptions are persistent connections.** They live in Phoenix Channels and broadcast via PubSub. Treat them as long-lived resources, not request/response.

## Architecture / Request Flow

```
HTTP POST → Phoenix Endpoint → Absinthe.Plug
              ↓
            Parse (query string → AST)
              ↓
            Validate (AST against schema)
              ↓
            Complexity check (reject if over budget)
              ↓
            Execute (resolve fields, run middleware)
              ├── Dataloader batches per-resolution phase
              └── Subscriptions: publish → Channel → all subscribers
              ↓
            Return JSON: %{data: ..., errors: ...}
```

## Decision Tree: Where Does This Logic Belong?

```
What kind of behavior?
├── Defines the API surface (types, fields, args)? → Schema / Type Notation
├── Computes a field value from parent + args + context? → Resolver
├── Cross-cutting concern (auth, logging, telemetry)? → Middleware
├── Batching cross-resolver DB loads? → Dataloader source
├── Long-lived push notifications? → Subscription field + PubSub topic
├── Real-time event emitted from a context? → Absinthe.Subscription.publish/3
└── Domain logic / DB writes / external service calls? → Context module (see phoenix-expert)
```

## Decision Tree: Resolver Strategy

```
What data shape does this field need?
├── Single entity by ID? → Resolver + context fetch_*
├── Filtered list? → Resolver + context list_* with args
├── Field on parent struct, no I/O? → No resolver (Absinthe auto-resolves)
├── Computed from parent (full_name from first/last)? → Resolver function on type
├── Association of parent (posts on user)? → Dataloader (NEVER inline Repo)
├── Mutation (write)? → Resolver + context create/update/delete
├── Authenticated user only? → Middleware before resolver
└── Subscription? → Subscription field + config callback returning topic
```

## Decision Tree: N+1 Mitigation

```
Why is this query slow?
├── Loading associations in a list? → Dataloader (batch by source + key)
├── Multiple queries for related data? → Single Ecto query with preload + select
├── Same resolver running many times per query? → Dataloader (caches within request)
├── Large list returned without pagination? → Add Relay-style cursor pagination
├── Field requires an external API call per item? → Custom Dataloader source (KV)
└── Query itself is too expensive? → Complexity limit + cost analysis
```

## Core Patterns

### Schema setup

```elixir
defmodule MyAppWeb.Schema do
  use Absinthe.Schema

  import_types MyAppWeb.Schema.Types.User
  import_types MyAppWeb.Schema.Types.Post

  query do
    @desc "Get a user by ID"
    field :user, :user do
      arg :id, non_null(:id)
      resolve &MyAppWeb.Resolvers.Users.get_user/3
    end

    @desc "List users with optional filtering"
    field :users, list_of(:user) do
      arg :role, :user_role
      arg :active, :boolean, default_value: true
      resolve &MyAppWeb.Resolvers.Users.list_users/3
    end
  end

  mutation do
    field :create_user, :user do
      arg :input, non_null(:create_user_input)
      resolve &MyAppWeb.Resolvers.Users.create_user/3
    end
  end

  subscription do
    field :user_updated, :user do
      arg :id, non_null(:id)

      config(fn %{id: id}, _info ->
        {:ok, topic: "user:#{id}"}
      end)
    end
  end

  # Dataloader wiring
  def context(ctx) do
    loader =
      Dataloader.new()
      |> Dataloader.add_source(MyApp.Accounts, MyApp.Accounts.dataloader_source())

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end
end
```

### Type definitions

```elixir
defmodule MyAppWeb.Schema.Types.User do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  object :user do
    field :id, non_null(:id)
    field :email, non_null(:string)
    field :name, :string
    field :role, :user_role

    # Associations via Dataloader — prevents N+1
    field :organization, :organization, resolve: dataloader(MyApp.Accounts)
    field :posts, list_of(:post), resolve: dataloader(MyApp.Content)

    # Computed field — cheap, no I/O
    field :display_name, :string do
      resolve fn user, _, _ ->
        {:ok, "#{user.first_name} #{user.last_name}"}
      end
    end
  end

  input_object :create_user_input do
    field :email, non_null(:string)
    field :name, non_null(:string)
    field :role, :user_role, default_value: :member
  end

  enum :user_role do
    value :admin, description: "Full access"
    value :member, description: "Standard access"
    value :viewer, description: "Read-only access"
  end
end
```

### Resolvers

```elixir
defmodule MyAppWeb.Resolvers.Users do
  alias MyApp.Accounts

  # Query — return {:ok, _} or {:error, _}
  def get_user(_parent, %{id: id}, _resolution) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> {:ok, user}
      {:error, :not_found} -> {:error, "User not found"}
    end
  end

  def list_users(_parent, args, _resolution) do
    {:ok, Accounts.list_users(args)}
  end

  # Mutation with auth context
  def create_user(_parent, %{input: input}, %{context: %{current_user: %{role: :admin}}}) do
    case Accounts.create_user(input) do
      {:ok, user} -> {:ok, user}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, format_changeset(changeset)}
    end
  end

  def create_user(_parent, _args, _resolution), do: {:error, "Not authorized"}

  defp format_changeset(changeset) do
    # See ecto-expert for Ecto.Changeset.traverse_errors patterns
    errors = MyAppWeb.Schema.Helpers.changeset_to_errors(changeset)
    %{message: "Validation failed", details: errors}
  end
end
```

### Middleware (auth, logging, metadata)

```elixir
defmodule MyAppWeb.Middleware.Authenticate do
  @behaviour Absinthe.Middleware

  def call(resolution, _config) do
    case resolution.context do
      %{current_user: _user} -> resolution
      _ -> Absinthe.Resolution.put_result(resolution, {:error, "Not authenticated"})
    end
  end
end

# Apply to a single field
field :admin_data, :admin_data do
  middleware MyAppWeb.Middleware.Authenticate
  resolve &MyAppWeb.Resolvers.Admin.get_data/3
end

# Apply to all mutations via the schema's middleware/3 callback
def middleware(middleware, _field, %{identifier: :mutation}) do
  [MyAppWeb.Middleware.Authenticate | middleware]
end
def middleware(middleware, _field, _object), do: middleware
```

### Dataloader (2.x — modern source)

```elixir
defmodule MyApp.Accounts do
  alias MyApp.Repo

  def dataloader_source do
    Dataloader.Ecto.new(Repo, query: &query/2)
  end

  # Customize per-schema query — runs once per batch, not per item
  def query(User, params) do
    User
    |> maybe_filter_active(params)
    |> order_by([u], asc: u.name)
  end

  def query(queryable, _params), do: queryable
end
```

```elixir
# In schema types — auto-batches per resolution phase
field :users, list_of(:user), resolve: dataloader(MyApp.Accounts)

# With args (passed as params to query/2)
field :active_users, list_of(:user) do
  resolve dataloader(MyApp.Accounts, :users, args: %{active: true})
end
```

**Rule:** Dataloader caches and batches *within a single GraphQL request*. Batching across multiple HTTP requests is not the goal — each request is its own batch boundary.

### Subscriptions

```elixir
# Schema — define the subscription field with config callback
subscription do
  field :user_updated, :user do
    arg :id, non_null(:id)

    # Config maps args to a topic; clients subscribe with the same args
    config(fn %{id: id}, _info ->
      {:ok, topic: "user:#{id}"}
    end)

    # Optional trigger — run a resolver when a mutation fires
    trigger :update_user, topic: fn %{id: id} -> "user:#{id}" end
  end
end

# Publishing from a context (after a write)
def update_user(user, attrs) do
  with {:ok, updated} <- user |> User.changeset(attrs) |> Repo.update() do
    Absinthe.Subscription.publish(MyAppWeb.Endpoint, updated, user_updated: "user:#{updated.id}")
    {:ok, updated}
  end
end
```

```elixir
# In endpoint.ex — wire up the subscription transport
socket "/socket", MyAppWeb.UserSocket,
  websocket: [path: "", connect_info: [session: @session_options]]
```

```elixir
# UserSocket
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: MyAppWeb.Schema

  def connect(%{"token" => token}, socket, _) do
    case MyApp.Accounts.verify_token(token) do
      {:ok, user} -> {:ok, Absinthe.Phoenix.Socket.put_options(socket, context: %{current_user: user})}
      _ -> :error
    end
  end

  def id(socket), do: nil
end
```

**Rule:** Subscriptions broadcast through Phoenix.PubSub. Topic naming matters — pick a `<resource>:<id>` convention and use the same shape in both `config:` (subscribe side) and `publish/3` (broadcast side).

### Complexity analysis (DoS protection)

```elixir
defmodule MyAppWeb.Schema do
  use Absinthe.Schema

  query do
    field :users, list_of(:user) do
      arg :limit, :integer, default_value: 20

      # Cost depends on the requested list size
      complexity fn %{limit: limit}, child_complexity ->
        limit * child_complexity
      end

      resolve &MyAppWeb.Resolvers.Users.list_users/3
    end
  end
end
```

```elixir
# In the Plug — reject queries above a complexity threshold
plug Absinthe.Plug,
  schema: MyAppWeb.Schema,
  analyze_complexity: true,
  max_complexity: 200
```

**Rule:** Without complexity limits, a single deeply-nested query (`users { posts { comments { author { posts { ... } } } } }`) can DoS your DB. Set `max_complexity` per-environment based on real query patterns, not aspirational ones.

### File uploads (Apollo upload spec)

```elixir
defmodule MyAppWeb.Schema do
  scalar :upload do
    parse fn %Plug.Upload{} = upload -> {:ok, upload}; _ -> :error end
    serialize fn _ -> raise "Uploads cannot be serialized" end
  end

  mutation do
    field :upload_avatar, :user do
      arg :file, non_null(:upload)

      resolve fn _, %{file: %Plug.Upload{} = upload}, %{context: %{current_user: user}} ->
        MyApp.Accounts.set_avatar(user, upload)
      end
    end
  end
end

# In endpoint — Absinthe.Plug.Parser handles the multipart format
plug Plug.Parsers,
  parsers: [:urlencoded, Absinthe.Plug.Parser, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()
```

## Anti-patterns

### Don't: call `Repo` inline from resolvers for associations

```elixir
# BAD — N+1 if `users` returns 100 results
field :organization, :organization do
  resolve fn user, _, _ ->
    {:ok, MyApp.Repo.get(Organization, user.organization_id)}
  end
end
```

**Why it bites:** GraphQL resolves each field independently. Listing 100 users with their organizations triggers 100 individual `Repo.get` calls. Database round-trips dominate response time.

**Instead:**

```elixir
# GOOD — Dataloader batches into a single SELECT ... WHERE id IN (...)
field :organization, :organization, resolve: dataloader(MyApp.Accounts)
```

Always reach for Dataloader on associations. Inline Repo is only acceptable for single-result root queries.

### Don't: return `{:ok, nil}` when you mean `{:error, _}`

```elixir
# BAD
def get_user(_, %{id: id}, _) do
  {:ok, MyApp.Repo.get(User, id)}  # nil if not found, but resolver returns :ok
end
```

**Why it bites:** GraphQL clients see a successful response with a null field. They can't tell the difference between "user exists but has no name" and "user doesn't exist." Errors disappear into nullable fields.

**Instead:**

```elixir
# GOOD
def get_user(_, %{id: id}, _) do
  case MyApp.Repo.get(User, id) do
    nil -> {:error, "User not found"}
    user -> {:ok, user}
  end
end
```

`{:error, _}` puts the failure in the `errors` array where clients expect to see it.

### Don't: put business logic in middleware

```elixir
# BAD — middleware doing domain decisions
defmodule MyAppWeb.Middleware.AutoCreateOrgIfMissing do
  def call(resolution, _) do
    user = resolution.context.current_user
    if user.organization_id == nil do
      {:ok, org} = MyApp.Accounts.create_default_org(user)
      put_in(resolution.context.current_user.organization_id, org.id)
    end
    resolution
  end
end
```

**Why it bites:** Middleware runs for every field it's attached to — a single query can fire it dozens of times. Side effects in middleware aren't transactional, aren't testable in isolation, and execute in unpredictable orderings as resolvers parallelize.

**Instead:** Put the auto-create logic in the context module (`MyApp.Accounts.ensure_org/1`). Middleware verifies state; contexts mutate state.

### Don't: skip `max_complexity`

```elixir
# BAD
plug Absinthe.Plug, schema: MyAppWeb.Schema
# (no analyze_complexity, no max_complexity — anything goes)
```

**Why it bites:** A malicious or accidental deeply-nested query can fan out into millions of resolver calls. Even with Dataloader, the orchestration cost crashes the BEAM under load. This is a known GraphQL DoS vector.

**Instead:** Always enable complexity analysis with a reasonable cap. Start with `max_complexity: 200` and tune up only after measuring real query costs in staging.

### Don't: leak Ecto.Changeset structs to GraphQL

```elixir
# BAD
def create_user(_, %{input: input}, _) do
  case Accounts.create_user(input) do
    {:ok, user} -> {:ok, user}
    {:error, changeset} -> {:error, changeset}  # Absinthe can't serialize this
  end
end
```

**Why it bites:** Absinthe sees a changeset, has no idea what to do with it, and either crashes serialization or returns an opaque struct dump. Clients get unparseable error payloads.

**Instead:** Convert the changeset to a structured error map before returning. (See `ecto-expert` for `Ecto.Changeset.traverse_errors/2` patterns.)

```elixir
# GOOD
{:error, %{message: "Validation failed", details: format_errors(changeset)}}
```

## Common Gotchas

- **Schema introspection is enabled by default** — anyone can query your schema's full shape via `__schema`. Disable in prod (`introspection: false` in `Absinthe.Plug` opts) or gate behind admin auth. Tooling (Apollo Studio, GraphiQL) needs introspection in dev only.
- **Dataloader batches per resolution phase, not per query** — multiple top-level fields can each have their own batch cycles. Heavy queries benefit from co-locating loads on the same parent.
- **Subscription `trigger:` runs in the publishing process** — heavy work in a triggered subscription publication blocks the mutation that fired it. Pre-compute the payload before publishing if possible.
- **`:id` type serializes as a string, not an integer** — GraphQL `ID` is always a string on the wire. Match this in your resolvers (`%{id: id}` is a string), and convert if you need integer DB lookups.
- **Nullable by default** — fields are nullable unless wrapped in `non_null/1`. Forgotten `non_null` lets nil leak into clients that don't expect it. Be explicit on required fields.
- **`context/1` runs once per request** — heavy work here (DB queries, external lookups) bloats every single request, including health checks and introspection. Keep it lean; lazy-load anything optional.
- **Resolvers run inside the request process** — long resolvers block other requests on the same connection (in Bandit's per-connection model). For slow work, `Task.async_stream` inside the resolver or push to Oban + return a polling/subscription handle.
- **`@deprecated` only signals — it doesn't reject** — deprecated fields still resolve. Track usage via telemetry before removing.

## Quick Reference

```
Field types:
  non_null(:string)             # required
  list_of(:user)                # nullable list of users
  list_of(non_null(:user))      # list of non-null users
  non_null(list_of(:user))      # required list (can be empty)

Resolver return values:
  {:ok, value}                  # success
  {:error, "message"}           # error string
  {:error, message: "...", code: 422, details: %{...}}  # structured error
  {:middleware, MyMiddleware, opts}  # delegate to middleware

Subscription publishing:
  Absinthe.Subscription.publish(endpoint, payload, field_name: "topic")

Dataloader helpers:
  resolve: dataloader(Source)
  resolve: dataloader(Source, :assoc_name, args: %{...})
  resolve: dataloader(Source, fn parent, args, ctx -> ... end)
```

## When to Load Deeper References

- Modeling complex types (Relay connections + cursor pagination, custom scalars, interfaces, unions)? → Read `references/schema-patterns.md`
- Writing query/mutation/subscription test helpers, simulating subscriptions, or wiring resolver context in tests? → Read `references/testing.md`
