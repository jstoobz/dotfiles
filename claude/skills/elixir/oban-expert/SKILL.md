---
name: oban-expert
description: Oban background job patterns including workers, queues, scheduling, unique jobs, retries, and testing
---

# Oban Expert

## Decision Tree: Oban vs Alternatives

```
What kind of background work?
├── Must survive app restarts? → Oban (DB-backed, durable)
├── Must be scheduled for later? → Oban (cron or scheduled_at)
├── Must be unique/deduplicated? → Oban (unique keys)
├── Must have retries with backoff? → Oban (built-in)
├── Ephemeral, fire-and-forget? → Task.Supervisor.start_child
├── Need result back immediately? → Task.async/await
├── Stateful background process? → GenServer
├── Event-driven cross-aggregate? → Process manager (Commanded)
└── Periodic polling/cleanup? → Oban cron OR :timer.send_interval
```

## Worker Pattern

```elixir
defmodule MyApp.Workers.SendEmail do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    priority: 1  # 0 = highest, 3 = lowest

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template}}) do
    user = MyApp.Accounts.get_user!(user_id)
    case MyApp.Mailer.send(user, template) do
      {:ok, _} -> :ok
      {:error, :rate_limited} -> {:snooze, 60}  # retry in 60s
      {:error, :invalid_email} -> {:discard, "invalid email"}
      {:error, reason} -> {:error, reason}  # triggers retry
    end
  end
end
```

**Return values from `perform/1`:**

- `:ok` — success, job completed
- `{:ok, result}` — success with result
- `{:error, reason}` — failure, will retry
- `{:snooze, seconds}` — re-enqueue after delay (not a failure)
- `{:discard, reason}` — permanent failure, no retry
- `{:cancel, reason}` — cancel job (Oban Pro)

## Queue Configuration

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    default: 10,           # 10 concurrent workers
    notifications: 5,
    invoices: 3,
    reporting: 1,          # Sequential for heavy operations
    webhooks: [limit: 10, paused: false]
  ],
  plugins: [
    Oban.Plugins.Pruner,     # Clean completed jobs
    Oban.Plugins.Stager,     # Stage scheduled jobs
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", MyApp.Workers.DailyCleanup},
      {"*/15 * * * *", MyApp.Workers.SyncData, args: %{type: "incremental"}}
    ]}
  ]

# config/test.exs — disable queues in tests
config :my_app, Oban, testing: :inline  # Jobs run synchronously
# OR
config :my_app, Oban, testing: :manual  # Jobs must be drained manually
```

## Job Insertion

```elixir
# Basic insert
%{user_id: user.id, template: "welcome"}
|> MyApp.Workers.SendEmail.new()
|> Oban.insert()

# With scheduling
%{report_id: id}
|> MyApp.Workers.GenerateReport.new(scheduled_at: DateTime.add(DateTime.utc_now(), 3600))
|> Oban.insert()

# With priority
%{data: data}
|> MyApp.Workers.ProcessImport.new(priority: 0, queue: :imports)
|> Oban.insert()

# Inside Ecto.Multi (transactional)
Ecto.Multi.new()
|> Ecto.Multi.insert(:user, User.changeset(%User{}, attrs))
|> Oban.insert(:welcome_email, fn %{user: user} ->
  MyApp.Workers.SendEmail.new(%{user_id: user.id, template: "welcome"})
end)
|> Repo.transaction()
```

## Unique Jobs

```elixir
use Oban.Worker,
  queue: :default,
  unique: [
    period: 300,                    # 5 minute uniqueness window
    states: [:available, :scheduled, :executing],
    keys: [:user_id, :action],      # Only these args matter for uniqueness
    on_conflict: :replace           # :raise, :replace, :discard, :update
  ]

# Insert — will be deduplicated within window
%{user_id: 123, action: "sync"}
|> MyApp.Workers.SyncUser.new()
|> Oban.insert()
```

## Error Handling and Retries

```elixir
use Oban.Worker,
  queue: :default,
  max_attempts: 5

# Custom backoff (default: exponential)
@impl Oban.Worker
def backoff(%Oban.Job{attempt: attempt}) do
  # Exponential: 2^attempt seconds (4, 8, 16, 32, 64...)
  trunc(:math.pow(2, attempt))
end

# In perform — control retry behavior
def perform(%Oban.Job{attempt: attempt, max_attempts: max} = job) do
  case do_work(job.args) do
    {:error, :transient} when attempt < max -> {:error, :transient}  # retry
    {:error, :transient} -> {:discard, "max retries exceeded"}
    {:error, :permanent} -> {:discard, "permanent failure"}
    {:ok, result} -> {:ok, result}
  end
end
```

## Testing

```elixir
# config/test.exs — choose mode
config :my_app, Oban, testing: :inline   # Runs perform synchronously
# OR
config :my_app, Oban, testing: :manual   # Requires drain_queue

# Assert job was enqueued
use Oban.Testing, repo: MyApp.Repo

test "enqueues welcome email on signup" do
  {:ok, user} = Accounts.create_user(%{email: "test@example.com"})

  assert_enqueued worker: MyApp.Workers.SendEmail,
    args: %{user_id: user.id, template: "welcome"}
end

# Refute job enqueued
refute_enqueued worker: MyApp.Workers.SendEmail

# Execute job directly in tests
test "sends email correctly" do
  user = insert(:user)
  assert :ok = perform_job(MyApp.Workers.SendEmail, %{user_id: user.id, template: "welcome"})
end

# Drain queue (manual mode)
assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :notifications)
```

## References

- `references/advanced-patterns.md` — Cron, plugins, batch jobs, multi-step pipelines
- `references/testing-recipes.md` — Test helpers, integration testing, drain patterns
