---
name: oban-expert
description: Oban background job patterns — workers, queues, scheduling, unique jobs, retries, telemetry, engines, and Oban Pro features (Workflow, Batch)
targets:
  elixir: "1.18+"
  oban: "2.18+"
  otp: "27+"
---

# Oban Expert

## When to Use This Skill

- Designing background jobs: workers, queues, scheduling, cron, retries
- Choosing between Oban and other concurrency primitives (Task, GenServer, plain async)
- Implementing unique jobs, idempotency, or deduplication logic
- Wiring telemetry events for observability and alerting
- Configuring engines (Postgres / SQLite Lite / MyXQL)
- Designing multi-step workflows or batched jobs (Oban Pro)
- **Skip this skill when working on synchronous workflows that don't need durability (use `beam-expert` for Task / GenServer), or event-sourced cross-aggregate workflows (use `commanded-expert` for Process Managers).**

## Mental Model

- **Oban is a durable work queue, not a stream processor.** Jobs are rows in a Postgres table. They survive crashes, restarts, and deploys. If your workload is a stream of events with backpressure, you want Broadway/GenStage instead.
- **At-least-once delivery is the default.** A job may run more than once if a worker crashes mid-execution. Workers must be idempotent — every job is potentially a retry.
- **The queue is the boundary.** Inserting a job is fast (one DB row); the work happens later in a worker process. This decouples request latency from work duration.
- **The `Pruner` keeps the table from growing forever.** Without it, completed/discarded jobs accumulate. With it, history is bounded — design any "did this job already run?" logic accordingly.

## Architecture / Job Flow

```
Producer side (request, controller, context):
  Oban.insert(MyWorker.new(args))   →  rows in `oban_jobs` table

Oban supervisor on each node:
  Stager       — promotes :scheduled jobs whose scheduled_at is past
  Plugins      — Cron, Pruner, Reindexer, Lifeline, etc.
  Per-queue producers
       ↓
       fetches `available` jobs (FOR UPDATE SKIP LOCKED)
       ↓
       runs Worker.perform/1 in a Task
       ↓
       updates row state: completed | retryable | discarded | cancelled
       ↓
       emits telemetry event ([:oban, :job, :stop] etc.)
```

## Decision Tree: Oban vs Alternatives

```
What kind of background work?
├── Must survive app restarts? → Oban (DB-backed, durable)
├── Must be scheduled for later (minutes, hours, cron)? → Oban (scheduled_at or Cron plugin)
├── Must be unique / deduplicated within a window? → Oban (unique keys)
├── Must retry with backoff on failure? → Oban (built-in)
├── Ephemeral fire-and-forget (no durability needed)? → Task.Supervisor.start_child
├── Need result back immediately (RPC-shaped)? → Task.async / Task.await
├── Stateful long-running process? → GenServer (see beam-expert)
├── Event-driven cross-aggregate workflow? → Process Manager (see commanded-expert)
├── Stream pipeline with backpressure? → Broadway / GenStage
└── Periodic polling / cleanup? → Oban Cron (durable) or :timer (ephemeral, restart-lossy)
```

## Decision Tree: Job Boundary Strategy

```
How should this work be split into jobs?
├── Single atomic operation? → One worker, one job
├── N independent items, all needing the same work? → Insert N jobs (worker per item)
│   └── Coordination needed at end? → Oban Pro Batch (callbacks: :success, :discard)
├── Pipeline of A → B → C, each step depends on prior? → Oban Pro Workflow (DAG)
├── Recurring schedule (daily report, hourly sync)? → Oban Cron
├── Fan-out then collect? → Multi-step jobs with explicit coordination state
└── User-initiated, must respond fast? → Insert from controller, return job ID for polling
```

## Decision Tree: Uniqueness Strategy

```
Should this job deduplicate?
├── Same args, same outcome, no point running twice? → unique: [period: N, keys: [...]]
├── Latest request wins (replace older queued job)? → unique: [..., on_conflict: :replace]
├── Always run, even if duplicate args? → No unique config (default)
├── Idempotency at the worker level (handler is safe to retry)? → No unique config + idempotent perform/1
└── Strict "exactly once" required? → unique: [...] + idempotent perform/1 (belt + suspenders)
```

## Core Patterns

### Worker

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
      {:error, :rate_limited} -> {:snooze, 60}              # retry in 60s, not a failure
      {:error, :invalid_email} -> {:discard, "invalid email"} # permanent, no retry
      {:error, reason} -> {:error, reason}                   # triggers retry
    end
  end
end
```

**Return values from `perform/1`:**

- `:ok` — success
- `{:ok, result}` — success with result (logged in telemetry meta)
- `{:error, reason}` — failure, will retry (up to `max_attempts`)
- `{:snooze, seconds}` — re-enqueue after delay (NOT a failure, doesn't count against attempts)
- `{:discard, reason}` — permanent failure, no retry, no future attempts
- `{:cancel, reason}` — cancel this job (Oban Pro)

### Queue + plugins configuration

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    default: 10,
    notifications: 5,
    invoices: 3,
    reporting: 1,                                   # serialize heavy work
    webhooks: [limit: 10, paused: false]
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},   # prune after 7 days
    Oban.Plugins.Stager,
    {Oban.Plugins.Reindexer, schedule: "@weekly"},      # rebuild indexes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)},  # rescue stuck jobs
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", MyApp.Workers.DailyCleanup},
      {"*/15 * * * *", MyApp.Workers.SyncData, args: %{type: "incremental"}}
    ]}
  ]

# config/test.exs — disable queues entirely in tests
config :my_app, Oban, testing: :inline   # jobs run synchronously in the calling process
# OR
config :my_app, Oban, testing: :manual   # jobs must be drained explicitly
```

### Job insertion (including transactional)

```elixir
# Basic insert
%{user_id: user.id, template: "welcome"}
|> MyApp.Workers.SendEmail.new()
|> Oban.insert()

# Schedule for later
%{report_id: id}
|> MyApp.Workers.GenerateReport.new(scheduled_at: DateTime.add(DateTime.utc_now(), 3600))
|> Oban.insert()

# With priority and explicit queue override
%{data: data}
|> MyApp.Workers.ProcessImport.new(priority: 0, queue: :imports)
|> Oban.insert()

# Inside Ecto.Multi — transactional with the originating write
Ecto.Multi.new()
|> Ecto.Multi.insert(:user, User.changeset(%User{}, attrs))
|> Oban.insert(:welcome_email, fn %{user: user} ->
  MyApp.Workers.SendEmail.new(%{user_id: user.id, template: "welcome"})
end)
|> Repo.transaction()
```

**Rule:** Job insertion in a `Multi` is critical — without it, the user might be created but the email job lost (or vice versa) if the surrounding transaction rolls back. Always co-commit the row and the job.

### Unique jobs

```elixir
defmodule MyApp.Workers.SyncUser do
  use Oban.Worker,
    queue: :default,
    unique: [
      period: 300,                                   # 5-minute uniqueness window
      states: [:available, :scheduled, :executing],
      keys: [:user_id, :action],                     # only these args matter
      on_conflict: :replace                          # :raise | :replace | :discard | :update
    ]
end

# Insert — duplicates within window become no-ops or replacements
%{user_id: 123, action: "sync"}
|> MyApp.Workers.SyncUser.new()
|> Oban.insert()
```

**Rule:** Unique config is per-worker, not per-insert. If you need different uniqueness rules from the same call site, override at insert time: `MyWorker.new(args, unique: [...])`.

### Custom retry backoff

```elixir
defmodule MyApp.Workers.WebhookCall do
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  # Exponential backoff with jitter — default is exponential without jitter
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    base = trunc(:math.pow(2, attempt))
    jitter = :rand.uniform(base)
    base + jitter
  end

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt, max_attempts: max} = job) do
    case do_webhook(job.args) do
      {:ok, _} -> :ok
      {:error, :rate_limited} -> {:snooze, 60}
      {:error, _reason} when attempt >= max -> {:discard, "max retries exceeded"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Telemetry observability

```elixir
# Attach a handler at boot
:telemetry.attach_many(
  "oban-handler",
  [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ],
  &MyApp.ObanTelemetry.handle_event/4,
  nil
)

defmodule MyApp.ObanTelemetry do
  def handle_event([:oban, :job, :stop], measure, %{job: job, state: :success}, _) do
    Logger.info("Oban job completed",
      worker: job.worker,
      duration_ms: System.convert_time_unit(measure.duration, :native, :millisecond)
    )
  end

  def handle_event([:oban, :job, :exception], measure, %{job: job, error: error}, _) do
    Logger.error("Oban job failed",
      worker: job.worker,
      error: inspect(error),
      attempt: job.attempt
    )
  end

  def handle_event(_, _, _, _), do: :ok
end
```

**Rule:** Don't write per-worker logging into `perform/1`. Telemetry handlers give you uniform observability across every job in the system, with structured metadata.

### Testing

```elixir
# config/test.exs
config :my_app, Oban, testing: :inline   # OR :manual

defmodule MyAppTest do
  use MyApp.DataCase
  use Oban.Testing, repo: MyApp.Repo

  test "enqueues welcome email on signup" do
    {:ok, _user} = Accounts.create_user(%{email: "test@example.com"})

    assert_enqueued worker: MyApp.Workers.SendEmail,
      args: %{user_id: _, template: "welcome"}
  end

  test "refute enqueued for non-eligible users" do
    refute_enqueued worker: MyApp.Workers.SendEmail
  end

  test "executes job synchronously" do
    user = insert(:user)
    assert :ok = perform_job(MyApp.Workers.SendEmail, %{user_id: user.id, template: "welcome"})
  end

  test "drains queue (manual mode)" do
    insert_oban_jobs(...)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :notifications)
  end
end
```

### Oban Pro: Workflow (DAG of jobs)

```elixir
# Requires Oban Pro license
defmodule MyApp.Workflows.CustomerOnboarding do
  use Oban.Pro.Workflow

  def new(customer_id) do
    new()
    |> add(:create, MyApp.Workers.CreateCustomer, %{id: customer_id})
    |> add(:notify, MyApp.Workers.NotifyCustomer, %{id: customer_id}, deps: [:create])
    |> add(:report, MyApp.Workers.GenerateReport, %{id: customer_id}, deps: [:notify])
  end
end

# Insert the entire workflow
MyApp.Workflows.CustomerOnboarding.new(customer.id) |> Oban.insert_all()
```

**Rule:** Workflows are an Oban Pro feature — for OSS-only setups, achieve the same with explicit dependent inserts in event handlers or process managers (see `commanded-expert`).

## Anti-patterns

### Don't: write workers that aren't idempotent

```elixir
# BAD
def perform(%Oban.Job{args: %{"order_id" => id}}) do
  order = Repo.get!(Order, id)
  MyApp.Payments.charge_card!(order)  # charges every time, no record check
  Repo.update!(Ecto.Changeset.change(order, status: :paid))
end
```

**Why it bites:** Oban delivers at-least-once. A worker crash after `charge_card!` succeeds but before `Repo.update!` commits leaves the order unpaid in the DB but charged. The retry charges the card again. The customer is double-billed.

**Instead:** Check the current state first; use idempotency keys with the payment provider; or wrap state changes in a database constraint that makes the second attempt a no-op.

```elixir
def perform(%Oban.Job{args: %{"order_id" => id}}) do
  order = Repo.get!(Order, id)
  case order.status do
    :paid -> :ok                        # already done, no-op
    :pending ->
      with {:ok, _} <- MyApp.Payments.charge_card(order, idempotency_key: "order-#{id}"),
           {:ok, _} <- mark_paid(order) do
        :ok
      end
  end
end
```

### Don't: insert jobs outside the originating transaction

```elixir
# BAD
def signup(attrs) do
  with {:ok, user} <- Repo.insert(User.changeset(%User{}, attrs)) do
    Oban.insert(MyApp.Workers.SendEmail.new(%{user_id: user.id, template: "welcome"}))
    {:ok, user}
  end
end
```

**Why it bites:** The user insert and the job insert are in separate transactions. If the surrounding logic later rolls back the user insert (e.g., a parent `Multi` fails), the job is still in the queue and runs against a non-existent user. Or the reverse — user persists but the job insert fails silently.

**Instead:** Use `Multi.insert/3` with `Oban.insert/2` so both writes commit (or both roll back) atomically.

### Don't: use Oban for low-latency request/response

```elixir
# BAD
def transform_image(conn, %{"file" => upload}) do
  job = Oban.insert!(MyApp.Workers.Transform.new(%{path: upload.path}))
  # ... loop polling for completion to return the result inline
end
```

**Why it bites:** Oban is for *durable* work; the latency from insert to execution is at least the queue tick interval (typically 1s). Polling adds more latency. For sub-second response work, use `Task` or do the work inline.

**Instead:** Use `Task.async/await` for one-shot CPU-bound work that needs a result, or `Task.Supervisor` for fire-and-forget. Reserve Oban for work that must survive a deploy mid-execution.

### Don't: skip the Pruner plugin

```elixir
# BAD
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [default: 10],
  plugins: [Oban.Plugins.Stager]   # no Pruner
```

**Why it bites:** Without the Pruner, the `oban_jobs` table grows without bound. Index size balloons, queries slow down, eventually you spend more time querying for the next job than running jobs. Production DBs have hit hundreds of millions of completed-but-unpruned rows.

**Instead:** Always include `{Oban.Plugins.Pruner, max_age: ...}` with a max_age that fits your retention/audit needs. 7 days is a common starting point.

### Don't: build worker control flow on `attempt` numbers without bounds

```elixir
# BAD
def perform(%Oban.Job{attempt: attempt} = job) do
  if attempt > 3 do
    notify_oncall(job)
  end
  do_work(job.args)
end
```

**Why it bites:** Coupling business logic to retry counts is brittle — bumping `max_attempts` breaks the threshold. The "alert oncall" logic is also fragile to retry semantics and doesn't compose with discard/cancel.

**Instead:** Use telemetry handlers (`[:oban, :job, :exception]`) to trigger oncall notifications based on job state, not retry count. Keep `perform/1` focused on the business operation.

## Common Gotchas

- **Default `max_attempts` is 20** — the per-worker default in Oban is high. Specify explicitly in `use Oban.Worker, max_attempts: N` to match your retry budget.
- **`scheduled_at` is honored at the next Stager tick** — there's a small delay (default 1s) between when scheduled time arrives and when the job becomes available. Don't expect millisecond precision.
- **`unique` keys must be JSON-encodable** — atoms in args become strings on the wire. `unique: [keys: [:user_id]]` matches against `%{"user_id" => 123}` after JSON round-trip; mismatched key types silently produce duplicates.
- **`{:snooze, n}` doesn't increment attempt count** — useful when retrying isn't a failure (rate limits, downstream maintenance windows). But snoozed jobs can theoretically loop forever — add a manual cap if needed.
- **`testing: :inline` runs jobs in the calling process** — perfect for unit tests; misleading if your job spawns its own processes (Tasks under it run normally, but the perform happens synchronously). Use `:manual` + `drain_queue/1` if you need to test concurrency behavior.
- **Telemetry handlers run in the worker process** — heavy work in a handler blocks the next job pick on that queue. Keep handlers fast; offload to another process if needed.
- **`Oban.Job` ID is a regular integer, not a UUID** — useful for logging and lookups, but don't expose it as a customer-facing identifier; it leaks job volume.
- **The `Lifeline` plugin rescues "stuck" executing jobs** — jobs marked `:executing` whose worker died without updating state get reset to `:available` after `rescue_after`. Crucial for crashes; can mask real bugs that leave jobs stuck legitimately.
- **Oban Engine choice affects features** — Postgres (default) supports everything; SQLite (`Oban.Engines.Lite`) is good for embedded/dev but lacks `FOR UPDATE SKIP LOCKED` semantics; MyXQL has its own quirks. Match the engine to the deploy target.
- **Inserting in a `Multi` step that depends on a prior insert** — use `Oban.insert/2` with the multi name (`:welcome_email`) and a function that receives prior changes, not a precomputed job struct, so the user_id is interpolated correctly.

## Quick Reference

```
Worker return values:
  :ok                          # success
  {:ok, result}                # success + result
  {:error, reason}             # retry (up to max_attempts)
  {:snooze, seconds}           # re-enqueue, doesn't count as attempt
  {:discard, reason}           # permanent failure, no retry
  {:cancel, reason}            # cancel job (Pro)

Job insertion:
  Worker.new(args)             # build a changeset
  Worker.new(args, opts)       # opts: queue, priority, scheduled_at, unique, ...
  Oban.insert(changeset)       # {:ok, %Oban.Job{}} | {:error, _}
  Oban.insert!(changeset)      # raises on error
  Oban.insert_all([changesets])

Multi integration:
  Multi.new() |> Oban.insert(:name, fn changes -> Worker.new(...) end) |> Repo.transaction()

Test helpers (use Oban.Testing):
  assert_enqueued worker: W, args: %{...}
  refute_enqueued worker: W
  perform_job(W, args)
  Oban.drain_queue(queue: :name)

Common plugins:
  Oban.Plugins.Pruner          # prune old jobs (REQUIRED for any production setup)
  Oban.Plugins.Stager          # promote scheduled jobs (REQUIRED)
  Oban.Plugins.Reindexer       # rebuild indexes weekly
  Oban.Plugins.Lifeline        # rescue stuck executing jobs
  Oban.Plugins.Cron            # cron-style schedules

Telemetry events:
  [:oban, :job, :start]        # job picked up
  [:oban, :job, :stop]         # job completed (success or controlled failure)
  [:oban, :job, :exception]    # job raised
  [:oban, :engine, :*]         # engine-level events
  [:oban, :plugin, :*]         # plugin-level events
```

## When to Load Deeper References

- Building cron jobs, batched/multi-step pipelines, or dynamic schedules with the Cron plugin? → Read `references/advanced-patterns.md`
- Writing integration tests with `drain_queue`, custom test helpers, or testing telemetry handlers? → Read `references/testing-recipes.md`
