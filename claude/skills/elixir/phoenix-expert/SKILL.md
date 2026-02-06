---
name: phoenix-expert
description: Phoenix framework patterns including plugs, routers, controllers, contexts, channels, and configuration
---

# Phoenix Expert

## Architecture: Request Flow

```
Request → Endpoint (plugs) → Router (pipelines) → Controller → Context → Repo/Domain
                                                 ↓
                                              View/JSON
```

## Decision Tree: Where Does This Code Go?

```
What kind of logic?
├── Business rules / domain logic? → Context module (lib/app/context.ex)
│   ├── Touches multiple schemas? → Context module (transaction boundary)
│   └── Single schema CRUD? → Context module (thin wrapper)
├── HTTP concern (headers, status, redirect)? → Controller or Plug
├── Data shape / validation? → Schema + Changeset
├── Request transformation / auth? → Plug (module or function)
├── Background processing? → Oban worker
├── Real-time push? → Channel or PubSub
├── Cross-cutting (logging, metrics)? → Plug or Telemetry handler
└── Reusable query logic? → Query module (MyApp.Accounts.UserQuery)
```

## Router Patterns

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Pipelines define plug stacks
  pipeline :api do
    plug :accepts, ["json"]
    plug MyAppWeb.AuthPlug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  # Scopes group routes under a path prefix
  scope "/api/v1", MyAppWeb.API.V1 do
    pipe_through :api
    resources "/users", UserController, only: [:index, :show, :create]
  end

  # Forward to another plug (e.g., GraphQL)
  forward "/graphql", Absinthe.Plug, schema: MyAppWeb.Schema
end
```

## Context Module Patterns

```elixir
defmodule MyApp.Accounts do
  @moduledoc "Public API for account management."
  alias MyApp.Repo
  alias MyApp.Accounts.{User, Organization}

  # Simple lookups
  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)

  # Create with changeset
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
  end
end
```

## Plug Patterns

```elixir
# Function plug — simple, inline in router/controller
def authenticate(conn, _opts) do
  case get_req_header(conn, "authorization") do
    ["Bearer " <> token] -> assign(conn, :token, token)
    _ -> conn |> send_resp(401, "Unauthorized") |> halt()
  end
end

# Module plug — reusable, testable
defmodule MyAppWeb.AuthPlug do
  import Plug.Conn
  def init(opts), do: opts
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- MyApp.Auth.verify(token) do
      assign(conn, :current_user, user)
    else
      _ -> conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end
end
```

## Controller Patterns

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  action_fallback MyAppWeb.FallbackController

  def show(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)
    render(conn, :show, user: user)
  end

  def create(conn, %{"user" => params}) do
    with {:ok, user} <- Accounts.create_user(params) do
      conn
      |> put_status(:created)
      |> render(:show, user: user)
    end
  end
end

# FallbackController handles {:error, _} from with blocks
defmodule MyAppWeb.FallbackController do
  use MyAppWeb, :controller
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn |> put_status(:unprocessable_entity) |> put_view(ErrorJSON) |> render(:error, changeset: changeset)
  end
  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> put_view(ErrorJSON) |> render(:"404")
  end
end
```

## Configuration

```
config/
├── config.exs      # Compile-time, shared defaults
├── dev.exs         # Dev overrides (debug, livereload)
├── test.exs        # Test overrides (sandbox, async)
├── prod.exs        # Prod compile-time (if needed)
└── runtime.exs     # Runtime config (env vars, secrets) — PREFERRED for prod
```

**Rule:** If the value comes from an environment variable, it goes in `runtime.exs`.

## Deployment (Releases)

```elixir
# Run migrations in a release (no Mix available)
defmodule MyApp.Release do
  def migrate do
    for repo <- Application.fetch_env!(:my_app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
```

## References

- `references/plugs-middleware.md` — Custom plug examples, Conn manipulation, pipeline design
- `references/configuration.md` — Runtime config patterns, endpoint config, PubSub setup
