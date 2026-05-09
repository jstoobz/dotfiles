---
name: phoenix-expert
description: Phoenix framework patterns for non-LiveView web work — controllers, routers, plug pipelines, contexts, channels, PubSub, releases, and runtime config
targets:
  elixir: "1.18+"
  phoenix: "1.8+"
  otp: "27+"
---

# Phoenix Expert

## When to Use This Skill

- Editing the router, plug pipelines, scopes, or verified routes (`~p`)
- Working on controllers, JSON modules, `action_fallback`, or `FallbackController`
- Structuring context modules and domain boundaries
- Writing function plugs or module plugs
- Setting up Phoenix.Channels or `Phoenix.PubSub` topics
- Configuring `runtime.exs`, the endpoint, or release deployment
- **Skip this skill when editing `.heex` templates, `Phoenix.Component`, `Phoenix.LiveComponent`, or LiveView callbacks (`mount/3`, `handle_event/3`, `handle_params/3`) — use `liveview-expert`.**

## Mental Model

- **Phoenix is Plug + conventions.** Every request is a `Plug.Conn` walking through a stack of transformations. Endpoint, router pipelines, controllers — all plugs. Once you internalize this, the framework's "magic" disappears.
- **Contexts are the domain boundary, not the database boundary.** A context is a Phoenix concept for "the public API of a bounded part of your domain" — it might wrap multiple schemas, multiple repos, or external services. Controllers talk to contexts; contexts talk to whatever they need.
- **Compile-time and runtime config are different worlds.** `config/config.exs` runs once at compile. `config/runtime.exs` runs on every boot. Secrets, env vars, and anything that varies per deploy belongs in `runtime.exs`. Forgetting this is the #1 release-time surprise.
- **The `Plug.Conn` is immutable.** Every plug returns a (possibly transformed) `conn`. Forgetting to return — or returning the wrong thing — silently breaks the pipeline.

## Architecture / Request Flow

```
Request
  → Endpoint plugs (parsers, static, session, sockets — runs for EVERY request)
    → Router (matches path)
      → Pipeline plugs (e.g., :api or :browser — selected by `pipe_through`)
        → Controller action
          → Context (your domain logic)
            → Repo / external services
          ← {:ok, result} | {:error, reason}
        → render(conn, :show, ...)  OR  action_fallback handles error tuple
      ← Plug.Conn with response
    ← halt()ed if a plug rejected
  ← Response sent
```

## Decision Tree: Where Does This Code Belong?

```
What kind of code is this?
├── Pure business rule / domain logic? → Context module (lib/my_app/<domain>.ex)
│   ├── Touches multiple schemas atomically? → Context with Ecto.Multi
│   └── Single-schema CRUD? → Context (thin wrapper, not the schema directly)
├── HTTP-shaped concern (status, redirect, headers)? → Controller
├── Stateful UI / WebSocket-rendered page? → LiveView (load liveview-expert)
├── Validation / data shape? → Schema + Changeset (see ecto-expert)
├── Request transformation / auth / rate limit? → Plug (function or module)
├── Background work / scheduled? → Oban worker (see oban-expert)
├── Real-time push to subscribers? → PubSub broadcast + Channel/LiveView subscribe
├── Cross-cutting (logging, metrics, tracing)? → Plug or Telemetry handler
└── Reusable query logic? → Query module (MyApp.Accounts.UserQuery)
```

## Decision Tree: Route Style

```
What kind of route?
├── Standard CRUD (index/show/new/create/edit/update/delete)? → resources/3
│   └── Subset only? → resources "/users", UserController, only: [:index, :show]
├── Single non-CRUD action? → get/post/put/delete with explicit path
├── Group of routes sharing pipeline + path prefix? → scope/3 with pipe_through
├── Versioned API? → scope "/api/v1", MyAppWeb.API.V1 do ... end
├── Mounting another app/plug (GraphQL, metrics)? → forward/2
├── LiveView page? → live "/path", MyLive (uses live_session in liveview-expert)
└── Static asset? → Endpoint Plug.Static, NOT in router
```

## Decision Tree: Plug Placement

```
Where should this plug run?
├── On EVERY request (parsers, sessions, sockets, request_id)? → Endpoint
├── On a class of routes (api vs browser, auth vs public)? → Router pipeline
├── On a single controller's actions? → plug/2 inside the controller module
│   └── Conditional? → plug MyPlug when action in [:create, :update]
├── Inline/one-off transformation in an action? → Function plug
└── Reusable across many controllers? → Module plug in MyAppWeb.Plugs.X
```

## Decision Tree: Compile-time vs Runtime Config

```
When is this value known?
├── Same across every environment, hardcoded? → config/config.exs (compile-time)
├── Differs per Mix env (dev/test/prod), known at compile time? → config/<env>.exs
├── From an environment variable, secret, or remote service? → config/runtime.exs
├── Depends on the running release/instance (node name, region)? → runtime.exs
└── Test-only override (sandbox, mock adapter)? → config/test.exs
```

**Rule:** If you ever feel the urge to use `System.get_env/1` outside `runtime.exs`, you're about to bake an env var into the compiled BEAM binary. Don't.

## Core Patterns

### Router with verified routes

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug MyAppWeb.Plugs.AuthenticateAPI
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    resources "/users", UserController
  end

  scope "/api/v1", MyAppWeb.API.V1, as: :api_v1 do
    pipe_through :api

    resources "/users", UserController, only: [:index, :show, :create]
  end

  forward "/graphql", Absinthe.Plug, schema: MyAppWeb.Schema
end
```

```heex
<!-- Verified routes anywhere in HEEx or Elixir code -->
<.link href={~p"/users"}>Users</.link>
<.link href={~p"/users/#{user}"}>{user.name}</.link>
<.link href={~p"/users?#{[page: 2]}"}>Next page</.link>
```

**Rule:** Use `~p` everywhere. It compile-checks paths against the router — typos fail at compile time, not in production. Old `Routes.user_path(conn, :show, user)` helpers still work but are legacy.

### Function plug

```elixir
def authenticate_api(conn, _opts) do
  with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
       {:ok, user} <- MyApp.Accounts.verify_token(token) do
    assign(conn, :current_user, user)
  else
    _ ->
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.json(%{error: "unauthorized"})
      |> halt()
  end
end
```

**Rule:** A plug ALWAYS returns a `conn`. If you reject the request, `halt(conn)` so downstream plugs are skipped. Forgetting `halt/1` lets the request continue with a half-rendered response — silent and confusing.

### Module plug

```elixir
defmodule MyAppWeb.Plugs.AuthenticateAPI do
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # same body as function plug
  end
end
```

**Rule:** Module plugs are for reusable plugs needing config or testing in isolation. `init/1` runs at compile time (in router) — keep it cheap and side-effect-free.

### Controller with `action_fallback`

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  action_fallback MyAppWeb.FallbackController

  alias MyApp.Accounts

  def show(conn, %{"id" => id}) do
    with {:ok, user} <- Accounts.fetch_user(id) do
      render(conn, :show, user: user)
    end
  end

  def create(conn, %{"user" => params}) do
    with {:ok, user} <- Accounts.create_user(params) do
      conn
      |> put_status(:created)
      |> render(:show, user: user)
    end
  end

  def update(conn, %{"id" => id, "user" => params}) do
    with {:ok, user} <- Accounts.fetch_user(id),
         {:ok, updated} <- Accounts.update_user(user, params) do
      render(conn, :show, user: updated)
    end
  end
end
```

```elixir
defmodule MyAppWeb.FallbackController do
  use MyAppWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MyAppWeb.ErrorJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> put_view(json: MyAppWeb.ErrorJSON) |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn |> put_status(:forbidden) |> put_view(json: MyAppWeb.ErrorJSON) |> render(:"403")
  end
end
```

**Rule:** With `action_fallback`, controllers stay focused on the happy path. Every `{:error, _}` from a `with` chain is dispatched to the fallback. (See `ecto-expert` for the changeset error-formatting helpers used in `MyAppWeb.ErrorJSON`.)

### JSON module (Phoenix 1.7+ — Views are deprecated)

```elixir
defmodule MyAppWeb.UserJSON do
  alias MyApp.Accounts.User

  def index(%{users: users}) do
    %{data: for(user <- users, do: data(user))}
  end

  def show(%{user: user}) do
    %{data: data(user)}
  end

  defp data(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      inserted_at: user.inserted_at
    }
  end
end
```

**Rule:** JSON modules are plain functions on assigns — no `use Phoenix.View`, no `render/2` macro. The controller's `render(conn, :show, user: user)` calls `UserJSON.show(%{user: user})`. Pure data shaping.

### Context module

```elixir
defmodule MyApp.Accounts do
  @moduledoc "Public API for account management."
  alias MyApp.Repo
  alias MyApp.Accounts.{User, Organization}

  # Read API — bang and non-bang variants
  def get_user(id), do: Repo.get(User, id)

  def fetch_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def list_users(filters \\ []), do: User |> apply_filters(filters) |> Repo.all()

  # Write API — returns {:ok, _} | {:error, _} for action_fallback
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  # Transaction boundary — Multi for related writes
  def create_user_with_org(user_attrs, org_attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
    |> Ecto.Multi.insert(:org, fn %{user: user} ->
      Organization.changeset(%Organization{owner_id: user.id}, org_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end
end
```

**Rule:** Contexts are the *only* place controllers should call into your domain. No `Repo.get` in controllers. Contexts can use Ecto, Oban, external APIs — whatever they need. (See `ecto-expert` for query composition and Multi patterns.)

### PubSub

```elixir
# Subscribe (typically in a LiveView mount or Channel join)
Phoenix.PubSub.subscribe(MyApp.PubSub, "user:#{user_id}")

# Broadcast (from a context, after a state change)
def update_user(user, attrs) do
  with {:ok, updated} <- user |> User.changeset(attrs) |> Repo.update() do
    Phoenix.PubSub.broadcast(MyApp.PubSub, "user:#{updated.id}", {:user_updated, updated})
    {:ok, updated}
  end
end

# Receive (any subscriber's GenServer/LiveView/Channel handle_info)
def handle_info({:user_updated, user}, state) do
  {:noreply, %{state | user: user}}
end
```

**Rule:** Topic naming convention matters — pick a scheme like `"<resource>:<id>"` and stick to it. Broadcasting from the context (not the controller) means the event fires regardless of which transport triggered the change.

### Phoenix.Channel

```elixir
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket
  channel "room:*", MyAppWeb.RoomChannel

  def connect(%{"token" => token}, socket, _connect_info) do
    case MyApp.Accounts.verify_token(token) do
      {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
      _ -> :error
    end
  end

  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

defmodule MyAppWeb.RoomChannel do
  use MyAppWeb, :channel

  @impl true
  def join("room:" <> room_id, _params, socket) do
    {:ok, assign(socket, :room_id, room_id)}
  end

  @impl true
  def handle_in("new_message", %{"body" => body}, socket) do
    broadcast!(socket, "new_message", %{body: body, user_id: socket.assigns.user_id})
    {:reply, :ok, socket}
  end
end
```

**Rule:** Each channel runs in its own process. Long-running work in `handle_in/3` blocks every other message on that channel. Push heavy work to a Task or Oban; reply with `{:noreply, socket}` and `push/3` the result later.

### Runtime config

```elixir
# config/runtime.exs — runs on every boot, even in releases
import Config

if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :my_app, MyAppWeb.Endpoint,
    url: [host: System.fetch_env!("PHX_HOST"), port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    secret_key_base: secret_key_base,
    server: true
end
```

**Rule:** `runtime.exs` is the only config file that can read environment variables in a release. Use `System.fetch_env!/1` (raises if missing) for required values; `System.get_env/2` (with default) for optional ones.

### Release migration task

```elixir
defmodule MyApp.Release do
  @app :my_app

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
```

```bash
# Invoke from the release
bin/my_app eval "MyApp.Release.migrate()"
```

## Anti-patterns

### Don't: put business logic in controllers

```elixir
# BAD
def create(conn, %{"user" => params}) do
  user = %User{} |> User.changeset(params) |> Repo.insert!()
  Repo.update_all(from(o in Organization, where: o.id == ^params["org_id"]),
    inc: [member_count: 1]
  )
  MyApp.Mailer.send_welcome(user)
  render(conn, :show, user: user)
end
```

**Why it bites:** Business logic in controllers is untestable without HTTP simulation, can't be reused (admin script, background job, GraphQL resolver all need their own copy), and breaks transactional guarantees (the email send happens whether the org update succeeds or not).

**Instead:** All of this belongs in `MyApp.Accounts.create_user_with_welcome/1` as a context function returning `{:ok, user}` or `{:error, _}`. Controller becomes a 2-line `with` chain.

### Don't: store secrets in `config/config.exs` or `config/prod.exs`

```elixir
# BAD — config/prod.exs
config :my_app, MyApp.Mailer,
  api_key: "sk_live_abc123def456..."   # baked into the compiled BEAM binary
```

**Why it bites:** Anything in `config/config.exs` or `config/<env>.exs` is read at compile time and frozen into the release artifact. The secret travels in the build, ends up in the Docker image, gets mirrored to your registry, may be logged. Rotating means rebuilding.

**Instead:**

```elixir
# GOOD — config/runtime.exs
config :my_app, MyApp.Mailer,
  api_key: System.fetch_env!("MAILER_API_KEY")
```

Secrets live in environment variables (or a secrets manager that surfaces them as env vars), read at boot.

### Don't: use `Phoenix.View` modules (Phoenix < 1.7)

```elixir
# BAD — deprecated since 1.7
defmodule MyAppWeb.UserView do
  use MyAppWeb, :view

  def render("show.json", %{user: user}), do: %{data: data(user)}
  defp data(user), do: %{id: user.id, email: user.email}
end
```

**Why it bites:** `Phoenix.View` is removed in modern Phoenix. New projects don't generate it. Mixed-style codebases get confusing fast — half the responses go through Views, half through JSON modules.

**Instead:** Use plain `MyAppWeb.UserJSON` or `MyAppWeb.UserHTML` modules with regular functions on assigns. Controllers `render(conn, :show, user: user)` calls `UserJSON.show(%{user: user})` directly.

### Don't: use `Routes.user_path(conn, :show, id)` — use `~p`

```elixir
# BAD (legacy path helpers)
<a href={Routes.user_path(@conn, :show, @user)}>{@user.name}</a>
```

**Why it bites:** Path helpers still work but they're legacy as of Phoenix 1.7. They don't compile-check paths against the router, so `Routes.user_path` typos die in production. They also make code grep-hostile (`grep "user_path"` doesn't find URL references).

**Instead:**

```heex
<.link navigate={~p"/users/#{@user}"}>{@user.name}</.link>
```

Verified routes are checked at compile time and grep cleanly with `rg '~p"/users'`.

### Don't: do heavy work in plugs

```elixir
# BAD
def call(conn, _opts) do
  user = MyApp.Accounts.fetch_user_with_full_data(conn.assigns.user_id)
  assign(conn, :user_with_data, user)
end
```

**Why it bites:** Plugs run on EVERY request that hits this pipeline. A 200ms DB call in an endpoint plug adds 200ms to every request, including health checks and 404s. Plugs are hot path — keep them lean.

**Instead:** Load only what auth/routing need (probably just user_id from a token). Let the controller fetch the full data only when the action actually needs it. Or load lazily via `Phoenix.LiveView.assign_async` if it's a LiveView.

## Common Gotchas

- **`~p` requires `Phoenix.VerifiedRoutes` import** — typically wired into `use MyAppWeb, :controller` and `use MyAppWeb, :live_view`. If you see "undefined sigil ~p" in a custom module, you're missing the import.
- **`config/config.exs` and `config/<env>.exs` are compile-time** — `System.get_env/1` calls in these files read the env at *compile* time, not at boot. The compiled value is frozen into the release. This catches everyone once.
- **Endpoint plugs run for static assets too** — `Plug.Static` is in the endpoint, so any plug above it runs for `/assets/app.js` requests. Be careful with auth plugs at the endpoint level.
- **`halt/1` is required to short-circuit** — returning `conn` without `halt(conn)` lets downstream plugs continue. This produces multi-render bugs: response gets sent twice, or the wrong status sticks.
- **Pipeline order in router matters** — `pipe_through [:browser, :auth]` runs `:browser` first, then `:auth`. Auth that depends on session must come *after* `:fetch_session`.
- **`Bandit` is the default adapter (since 1.7)** — most Cowboy-era documentation still works, but socket upgrades and `:sec_websocket_protocol` handling differ slightly. If a third-party lib breaks on upgrade, suspect adapter mismatch.
- **`Phoenix.PubSub` topics are strings, not atoms** — `Phoenix.PubSub.subscribe(MyApp.PubSub, :users)` silently fails to match a `broadcast(MyApp.PubSub, "users", ...)`. Always use the same string both sides.
- **Channel processes are per-connection** — every WebSocket client gets its own channel process. State in a channel doesn't shard or share. For shared state, use ETS, a GenServer, or PubSub-driven coordination.

## Quick Reference

```
Common Conn helpers:
  put_status(conn, 201)             # set HTTP status
  put_resp_header(conn, "x-foo", "bar")
  put_resp_content_type(conn, "application/json")
  fetch_query_params(conn)          # populates conn.query_params
  fetch_session(conn)               # required before get_session
  assign(conn, :user, user)         # sets conn.assigns.user
  halt(conn)                        # stop pipeline (required after rejection)
  redirect(conn, to: ~p"/login")
  json(conn, %{ok: true})           # quick JSON response
  text(conn, "ok")                  # quick text response

Verified routes:
  ~p"/users"                        # static path
  ~p"/users/#{user}"                # interpolation (uses Phoenix.Param)
  ~p"/users?#{[page: 2, q: "foo"]}" # query string from keyword list
  ~p"/api/v1/users/#{user}"

Pipeline phases (typical browser flow):
  :accepts → :fetch_session → :fetch_live_flash
    → :put_root_layout → :protect_from_forgery
    → :put_secure_browser_headers → custom auth → controller
```

## When to Load Deeper References

- Designing a custom plug with complex Conn manipulation, conditional pipelines, or testing in isolation? → Read `references/plugs-middleware.md`
- Configuring runtime env, endpoint, PubSub adapter, or release boot scripts in detail? → Read `references/configuration.md`
