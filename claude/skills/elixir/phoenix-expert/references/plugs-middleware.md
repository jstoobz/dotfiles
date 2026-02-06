# Plugs and Middleware Reference

## Plug Types

### Function Plug

Simple, defined inline in a controller or router module.

```elixir
# In a controller
plug :authenticate when action in [:create, :update, :delete]

defp authenticate(conn, _opts) do
  case get_req_header(conn, "authorization") do
    ["Bearer " <> token] ->
      case MyApp.Auth.verify_token(token) do
        {:ok, user} -> assign(conn, :current_user, user)
        {:error, _} -> conn |> send_resp(401, "Invalid token") |> halt()
      end
    _ ->
      conn |> send_resp(401, "Missing authorization") |> halt()
  end
end
```

### Module Plug

Reusable across modules, testable independently.

```elixir
defmodule MyAppWeb.Plugs.RequireRole do
  import Plug.Conn

  def init(opts), do: Keyword.fetch!(opts, :role)

  def call(conn, required_role) do
    user = conn.assigns[:current_user]

    if user && user.role == required_role do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.put_view(MyAppWeb.ErrorJSON)
      |> Phoenix.Controller.render("403.json")
      |> halt()
    end
  end
end

# Usage in router:
plug MyAppWeb.Plugs.RequireRole, role: :admin
```

## Conn Manipulation

### Reading Request Data

```elixir
# Headers
get_req_header(conn, "content-type")    # ["application/json"]
get_req_header(conn, "authorization")   # ["Bearer ..."]

# Query params (already parsed)
conn.query_params["page"]

# Path params
conn.path_params["id"]

# Body params (parsed by Plug.Parsers)
conn.body_params["user"]

# All merged params
conn.params  # query + path + body
```

### Setting Response Data

```elixir
conn
|> put_status(:created)                           # HTTP status
|> put_resp_header("x-request-id", request_id)    # Response header
|> put_resp_content_type("application/json")       # Content type
|> assign(:current_user, user)                     # Assign for views
|> put_session(:user_id, user.id)                  # Session data
|> put_flash(:info, "Success!")                    # Flash message
```

### Halting the Pipeline

```elixir
# halt() prevents further plugs from executing
conn
|> send_resp(401, "Unauthorized")
|> halt()

# IMPORTANT: Always halt() after sending a response in a plug
# Otherwise downstream plugs will try to send another response
```

## Common Plug Patterns

### Rate Limiting

```elixir
defmodule MyAppWeb.Plugs.RateLimit do
  import Plug.Conn

  def init(opts) do
    %{
      max_requests: Keyword.get(opts, :max_requests, 100),
      window_ms: Keyword.get(opts, :window_ms, 60_000)
    }
  end

  def call(conn, %{max_requests: max, window_ms: window}) do
    key = rate_limit_key(conn)
    case MyApp.RateLimiter.check(key, max, window) do
      {:ok, remaining} ->
        put_resp_header(conn, "x-ratelimit-remaining", to_string(remaining))
      {:error, :rate_limited} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> send_resp(429, "Rate limited")
        |> halt()
    end
  end

  defp rate_limit_key(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    "rate_limit:#{ip}"
  end
end
```

### Request Logging

```elixir
defmodule MyAppWeb.Plugs.RequestLogger do
  require Logger
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      Logger.info("request",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: duration_ms
      )

      conn
    end)
  end
end
```

### CORS

```elixir
defmodule MyAppWeb.Plugs.CORS do
  import Plug.Conn

  @allowed_origins ["https://app.example.com"]

  def init(opts), do: opts

  def call(%{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    put_cors_headers(conn)
  end

  defp put_cors_headers(conn) do
    origin = get_req_header(conn, "origin") |> List.first()

    if origin in @allowed_origins do
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE")
      |> put_resp_header("access-control-allow-headers", "content-type, authorization")
      |> put_resp_header("access-control-max-age", "86400")
    else
      conn
    end
  end
end
```

## Pipeline Design

```elixir
# Layer plugs from general to specific
pipeline :api do
  plug :accepts, ["json"]
  plug MyAppWeb.Plugs.RequestLogger
  plug MyAppWeb.Plugs.CORS
  plug MyAppWeb.Plugs.RateLimit, max_requests: 100
  plug MyAppWeb.Plugs.Authenticate
end

# Scoped pipelines for different auth levels
pipeline :authenticated do
  plug MyAppWeb.Plugs.RequireAuth
end

pipeline :admin do
  plug MyAppWeb.Plugs.RequireAuth
  plug MyAppWeb.Plugs.RequireRole, role: :admin
end

scope "/api" do
  pipe_through [:api, :authenticated]
  # Protected routes
end

scope "/admin" do
  pipe_through [:api, :admin]
  # Admin-only routes
end
```

## Testing Plugs

```elixir
defmodule MyAppWeb.Plugs.RequireRoleTest do
  use MyAppWeb.ConnCase, async: true

  test "allows users with correct role" do
    conn =
      build_conn()
      |> assign(:current_user, %{role: :admin})
      |> MyAppWeb.Plugs.RequireRole.call(:admin)

    refute conn.halted
  end

  test "rejects users without correct role" do
    conn =
      build_conn()
      |> assign(:current_user, %{role: :member})
      |> MyAppWeb.Plugs.RequireRole.call(:admin)

    assert conn.halted
    assert conn.status == 403
  end
end
```
