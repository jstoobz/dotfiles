# Phoenix Configuration Reference

## Configuration File Hierarchy

```
config/
├── config.exs      # Base config, imported by all envs (compile-time)
├── dev.exs         # Development overrides
├── test.exs        # Test overrides
├── prod.exs        # Production compile-time (rarely used)
└── runtime.exs     # Runtime config (env vars) — loaded at boot
```

**Order of evaluation:**

1. `config.exs` (always, at compile time)
2. `{env}.exs` (per-environment, at compile time)
3. `runtime.exs` (at application start, has access to env vars)

**Rule of thumb:**

- Static defaults → `config.exs`
- Environment-specific overrides → `dev.exs` / `test.exs`
- Anything from env vars or secrets → `runtime.exs`

## Endpoint Configuration

```elixir
# config/config.exs — shared defaults
config :my_app, MyAppWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: MyAppWeb.ErrorJSON]],
  pubsub_server: MyApp.PubSub

# config/dev.exs — development
config :my_app, MyAppWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [node: ["scripts/watch.js", cd: Path.expand("../client", __DIR__)]]

# config/test.exs — testing
config :my_app, MyAppWeb.Endpoint,
  http: [port: 4002],
  server: false  # Don't start HTTP server in tests

# config/runtime.exs — production
config :my_app, MyAppWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"],
  http: [
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
```

## Database Configuration

```elixir
# config/dev.exs
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev",
  port: 5432,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

# config/test.exs
config :my_app, MyApp.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,  # Required for async tests
  pool_size: 10

# config/runtime.exs
config :my_app, MyApp.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true,
  ssl_opts: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
```

## PubSub Configuration

```elixir
# config/config.exs — local PubSub (development)
config :my_app, MyApp.PubSub,
  adapter: Phoenix.PubSub.PG2

# In supervision tree (application.ex):
{Phoenix.PubSub, name: MyApp.PubSub}

# Usage:
Phoenix.PubSub.subscribe(MyApp.PubSub, "topic:#{id}")
Phoenix.PubSub.broadcast(MyApp.PubSub, "topic:#{id}", {:event, payload})
```

## Logger Configuration

```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

# config/dev.exs — verbose
config :logger, level: :debug

# config/test.exs — quiet
config :logger, level: :warning

# config/runtime.exs — structured for production
config :logger,
  level: String.to_atom(System.get_env("LOG_LEVEL") || "info")
```

## Application Environment Patterns

```elixir
# Reading config at runtime
Application.get_env(:my_app, :feature_flag, false)
Application.fetch_env!(:my_app, :required_setting)

# Module-level config access (compile-time — avoid for runtime values)
@pool_size Application.compile_env(:my_app, [:repo, :pool_size], 10)

# Runtime config with fallback
def timeout do
  Application.get_env(:my_app, :request_timeout, 30_000)
end
```

## Feature Flags with FunWithFlags

```elixir
# config/config.exs
config :fun_with_flags, :cache,
  enabled: true,
  ttl: 900  # 15 minutes

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: MyApp.Repo

# Usage
if FunWithFlags.enabled?(:new_feature) do
  new_behavior()
else
  old_behavior()
end

# Actor-based flags
FunWithFlags.enabled?(:beta_feature, for: current_user)
```

## Secrets Management

```elixir
# config/runtime.exs — always use runtime for secrets
config :my_app,
  encryption_key: System.fetch_env!("ENCRYPTION_KEY"),
  api_key: System.fetch_env!("EXTERNAL_API_KEY")

# .envrc (local development — never commit)
export ENCRYPTION_KEY="dev-key-not-for-production"
export DATABASE_URL="postgres://localhost:5432/my_app_dev"

# NEVER put secrets in config.exs, dev.exs, or any committed file
```

## Release Configuration

```elixir
# mix.exs — release config
def project do
  [
    releases: [
      my_app: [
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  ]
end

# rel/env.sh.eex — runtime environment for releases
#!/bin/sh
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=my_app@${HOSTNAME}
```
