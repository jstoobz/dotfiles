# Oban Advanced Patterns Reference

## Cron Jobs

```elixir
# In Oban config
plugins: [
  {Oban.Plugins.Cron, crontab: [
    {"0 2 * * *", MyApp.Workers.DailyCleanup},                    # 2am daily
    {"*/15 * * * *", MyApp.Workers.SyncData},                     # Every 15 min
    {"0 0 1 * *", MyApp.Workers.MonthlyReport},                   # 1st of month
    {"0 9 * * 1-5", MyApp.Workers.WeekdayDigest},                 # 9am weekdays
    {"@reboot", MyApp.Workers.StartupTask}                        # On app start
  ]}
]

# Cron worker — args are always %{} unless configured
defmodule MyApp.Workers.DailyCleanup do
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  @impl true
  def perform(%Oban.Job{}) do
    MyApp.Cleanup.remove_stale_records()
    :ok
  end
end
```

## Plugins

```elixir
plugins: [
  # Prune completed/discarded jobs after 7 days
  {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},

  # Stage scheduled jobs (required)
  Oban.Plugins.Stager,

  # Rescue orphaned jobs (stuck in executing after crash)
  {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},

  # Reindex for performance (Postgres)
  {Oban.Plugins.Reindexer, schedule: "@weekly"}
]
```

## Batch Processing Pattern

```elixir
defmodule MyApp.Workers.ImportBatch do
  use Oban.Worker, queue: :imports, max_attempts: 3

  # Split large work into batches
  def enqueue_import(items) do
    items
    |> Enum.chunk_every(100)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, batch_num} ->
      %{items: chunk, batch: batch_num, total_batches: div(length(items), 100) + 1}
      |> new()
    end)
    |> Oban.insert_all()
  end

  @impl true
  def perform(%Oban.Job{args: %{"items" => items, "batch" => batch}}) do
    results = Enum.map(items, &process_item/1)
    failures = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failures) do
      :ok
    else
      {:error, "#{length(failures)} items failed in batch #{batch}"}
    end
  end
end
```

## Multi-Step Pipeline

```elixir
# Step 1: Validate
defmodule MyApp.Workers.ValidateImport do
  use Oban.Worker, queue: :imports

  def perform(%Oban.Job{args: %{"import_id" => id}}) do
    case MyApp.Imports.validate(id) do
      {:ok, _} ->
        # Enqueue next step
        %{import_id: id}
        |> MyApp.Workers.ProcessImport.new()
        |> Oban.insert()
        :ok
      {:error, reason} ->
        {:discard, reason}
    end
  end
end

# Step 2: Process
defmodule MyApp.Workers.ProcessImport do
  use Oban.Worker, queue: :imports

  def perform(%Oban.Job{args: %{"import_id" => id}}) do
    case MyApp.Imports.process(id) do
      {:ok, _} ->
        %{import_id: id}
        |> MyApp.Workers.NotifyComplete.new()
        |> Oban.insert()
        :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Rate Limiting (Without Oban Pro)

```elixir
defmodule MyApp.Workers.RateLimitedWorker do
  use Oban.Worker,
    queue: :external_api,
    max_attempts: 5,
    unique: [period: 1, keys: [:api_endpoint]]  # 1 per second per endpoint

  @impl true
  def perform(%Oban.Job{args: args}) do
    case MyApp.ExternalAPI.call(args) do
      {:ok, result} -> {:ok, result}
      {:error, :rate_limited} -> {:snooze, 5}  # Back off 5 seconds
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def backoff(%Oban.Job{attempt: attempt}) do
    # Jittered exponential: 2^attempt ± random
    base = trunc(:math.pow(2, attempt))
    jitter = :rand.uniform(base)
    base + jitter
  end
end
```

## Job Cancellation

```elixir
# Cancel a specific job
Oban.cancel_job(job_id)

# Cancel all jobs matching criteria
import Ecto.Query
from(j in Oban.Job,
  where: j.worker == "MyApp.Workers.SyncUser",
  where: j.state in ["available", "scheduled"]
)
|> MyApp.Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])
```

## Queue Management

```elixir
# Pause a queue
Oban.pause_queue(queue: :imports)

# Resume
Oban.resume_queue(queue: :imports)

# Scale queue concurrency at runtime
Oban.scale_queue(queue: :imports, limit: 20)

# Check queue stats
Oban.check_queue(queue: :imports)
```
