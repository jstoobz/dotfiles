---
name: commanded-expert
description: Commanded CQRS/event-sourcing patterns for aggregates, commands, events, process managers, projections, and event handlers
targets:
  elixir: "1.18+"
  commanded: "1.4+"
  otp: "27+"
---

# Commanded Expert

## When to Use This Skill

- Designing or modifying an aggregate, command, event, process manager, or projection
- Choosing between strong vs eventual consistency for a dispatch
- Debugging event replay, snapshot mismatches, or stuck process managers
- Adding event versioning / upcasting after a schema change
- Skip this skill when working on plain Ecto reads or non-event-sourced contexts (use `ecto-expert`)

## Mental Model

- **Commands express intent; events express fact.** Commands can be rejected. Events are immutable history.
- **Aggregates are pure functions over event history.** `execute/2` decides what events to emit; `apply/2` rebuilds state from events. **No I/O inside either.**
- **The event store is the source of truth, not your read models.** Projections can be rebuilt from scratch by replaying events.
- **Writes and reads are separate.** Dispatching a command does not synchronously update read models — they catch up via event handlers (eventual consistency).
- **Process managers coordinate across aggregates.** When event A in aggregate X must trigger command B in aggregate Y, that's a process manager — not an event handler with a side dispatch.

## Architecture / Request Flow

```
Command Dispatch:
  Caller → Router → Aggregate.execute(state, command)
                          ↓ returns events (or {:error, reason})
                    Event Store (append to stream)
                          ↓
                    Subscribers (async unless :strong consistency)
                          ├── Projections      → Read models (Ecto)
                          ├── Process Managers → Dispatch new commands
                          └── Event Handlers   → Side effects (email, webhook)

Aggregate state on cold load:
  Event Store → replay events → Aggregate.apply(state, event) for each → current state
                                  (or load snapshot + replay tail events)
```

## Decision Tree: Where Does This Logic Belong?

```
What kind of behavior?
├── Validates intent + decides what happened? → Aggregate (execute/2)
├── Updates aggregate state from a fact? → Aggregate (apply/2)
├── Reacts to events with new commands across aggregates? → Process Manager
├── Builds a queryable read model? → Projection (Commanded.Projections.Ecto)
├── Triggers a side effect (email, webhook, notification)? → Event Handler
├── Runs on a schedule, not in response to an event? → Oban worker (outside Commanded)
└── Cross-cutting concern (logging, metrics)? → Commanded middleware
```

## Decision Tree: Aggregate vs Process Manager

```
Where does this multi-step workflow live?
├── All within one aggregate's invariants? → Aggregate (execute returns multiple events)
├── Spans multiple aggregates / streams? → Process Manager
│   ├── Linear flow (A done → do B → do C)? → Process Manager with state machine
│   └── Saga with compensation (rollback on failure)? → Process Manager + compensating commands
├── Driven by external trigger (cron, webhook)? → Oban or external dispatcher → command
└── One event, one side effect, no new commands? → Event Handler (not Process Manager)
```

## Decision Tree: Consistency Mode

```
What does the caller need after dispatch returns?
├── Just acknowledgement that command was accepted? → :eventual (default, fastest)
├── Read model must reflect the change before responding (e.g., redirect after create)? → :strong
│   └── Cost: dispatch blocks until ALL strong handlers complete
├── Specific projection updated, others can lag? → :strong with explicit handler list
│   └── dispatch(cmd, consistency: [MyApp.Projections.UserList])
└── Fire-and-forget background work? → :eventual + GenServer/Oban for retry
```

## Decision Tree: Snapshot or Replay?

```
How long does aggregate replay take on cold load?
├── < 100 events per stream? → No snapshots needed
├── 100-1,000 events, occasional load? → No snapshots needed (replay is cheap)
├── 1,000-10,000 events, frequent load? → Enable snapshots (every N events)
├── Long-lived aggregates accumulating events? → Snapshots + consider stream archival
└── Aggregate state shape changing? → Bump @snapshot_version, will rebuild from events
```

## Core Patterns

### Command (intent)

```elixir
defmodule MyApp.Accounts.Commands.RegisterUser do
  @enforce_keys [:user_id, :email, :name]
  defstruct [:user_id, :email, :name]

  use Vex.Struct
  validates :user_id, uuid: true
  validates :email, presence: true, format: ~r/@/
  validates :name, presence: true, length: [min: 1]
end
```

**Rule:** Commands are plain structs with validation. The `user_id` (or `aggregate_id`) is required so the router can dispatch to the right stream.

### Event (fact)

```elixir
defmodule MyApp.Accounts.Events.UserRegistered do
  @derive Jason.Encoder
  defstruct [:user_id, :email, :name, :registered_at]
end
```

**Rule:** Events are immutable. Once an event is in the store, you can never rename a field or change semantics — only add new fields (with default nil) or write a new event version + upcaster.

### Aggregate

```elixir
defmodule MyApp.Accounts.User do
  @snapshot_version 1   # bump whenever the struct shape below changes
  defstruct [:user_id, :email, :name, :status]

  alias MyApp.Accounts.Commands.{RegisterUser, UpdateEmail}
  alias MyApp.Accounts.Events.{UserRegistered, EmailUpdated}

  # execute/2 — given current state and a command, return events (or error)
  def execute(%__MODULE__{user_id: nil}, %RegisterUser{} = cmd) do
    %UserRegistered{
      user_id: cmd.user_id,
      email: cmd.email,
      name: cmd.name,
      registered_at: DateTime.utc_now()
    }
  end

  def execute(%__MODULE__{}, %RegisterUser{}), do: {:error, :already_registered}

  def execute(%__MODULE__{user_id: nil}, _), do: {:error, :user_not_registered}

  def execute(%__MODULE__{email: same}, %UpdateEmail{email: same}), do: []  # no-op

  def execute(%__MODULE__{}, %UpdateEmail{} = cmd) do
    %EmailUpdated{user_id: cmd.user_id, email: cmd.email, updated_at: DateTime.utc_now()}
  end

  # apply/2 — given current state and an event, return new state
  def apply(%__MODULE__{} = state, %UserRegistered{} = ev) do
    %__MODULE__{state | user_id: ev.user_id, email: ev.email, name: ev.name, status: :active}
  end

  def apply(%__MODULE__{} = state, %EmailUpdated{email: email}) do
    %__MODULE__{state | email: email}
  end
end
```

**Rule:** `execute/2` and `apply/2` must be **pure** — no `Repo`, no `HTTPoison`, no external reads. **Exception:** timestamps (`DateTime.utc_now()`) and UUIDs may be generated *inside* `execute/2` to stamp a value into the event itself. The event then carries that timestamp forever — replaying the event uses the original value, preserving determinism. Never read external state to *decide* what events to emit; the aggregate struct is the only input.

### Router

```elixir
defmodule MyApp.Router do
  use Commanded.Commands.Router

  alias MyApp.Accounts.User
  alias MyApp.Accounts.Commands.{RegisterUser, UpdateEmail}

  identify(User, by: :user_id, prefix: "user-")

  dispatch([RegisterUser, UpdateEmail],
    to: User,
    lifespan: MyApp.Accounts.UserLifespan
  )
end
```

### Process Manager (cross-aggregate workflow)

```elixir
defmodule MyApp.Onboarding.WelcomeProcess do
  use Commanded.ProcessManagers.ProcessManager,
    application: MyApp.CommandedApp,
    name: __MODULE__

  defstruct [:user_id, :status]

  alias MyApp.Accounts.Events.UserRegistered
  alias MyApp.Notifications.Commands.SendWelcomeEmail

  # interested?/1 — what events start or continue this process?
  def interested?(%UserRegistered{user_id: id}), do: {:start, id}

  # handle/2 — given state and event, return commands to dispatch
  def handle(%__MODULE__{}, %UserRegistered{user_id: id, email: email, name: name}) do
    %SendWelcomeEmail{user_id: id, email: email, name: name}
  end

  # apply/2 — track process state if you need it across events
  def apply(%__MODULE__{} = state, %UserRegistered{user_id: id}) do
    %__MODULE__{state | user_id: id, status: :welcomed}
  end

  # Tear down the process manager when the workflow completes.
  # Without this, state persists indefinitely.
  def apply(%__MODULE__{} = state, %WelcomeEmailSent{}) do
    {:stop, %__MODULE__{state | status: :completed}}
  end
end
```

**Rule:** Process Manager state persists across restarts — it's stored in the event store like any other stream. Return `{:stop, new_state}` from `apply/2` when the workflow completes, otherwise zombie process managers accumulate forever.

### Projection (read model)

```elixir
defmodule MyApp.Accounts.Projections.UserProjection do
  use Commanded.Projections.Ecto,
    application: MyApp.CommandedApp,
    repo: MyApp.Repo,
    name: "Accounts.UserProjection",
    consistency: :eventual

  alias MyApp.Accounts.Events.{UserRegistered, EmailUpdated}
  alias MyApp.Accounts.ReadModels.User

  project(%UserRegistered{} = ev, _meta, fn multi ->
    Ecto.Multi.insert(multi, :user, %User{
      id: ev.user_id,
      email: ev.email,
      name: ev.name,
      registered_at: ev.registered_at
    })
  end)

  project(%EmailUpdated{user_id: id, email: email}, _meta, fn multi ->
    Ecto.Multi.update_all(multi, :user, from(u in User, where: u.id == ^id), set: [email: email])
  end)
end
```

**Rule:** Projections use `Ecto.Multi` so the projection write and Commanded's tracking offset are committed atomically. Never bypass the multi. (See `ecto-expert` for read-model schema design and Multi composition patterns.)

### Event Handler (side effect)

```elixir
defmodule MyApp.Notifications.WelcomeEmailHandler do
  use Commanded.Event.Handler,
    application: MyApp.CommandedApp,
    name: __MODULE__,
    consistency: :eventual

  alias MyApp.Accounts.Events.UserRegistered
  alias MyApp.Notifications.EmailLog

  # Idempotent: at-least-once delivery means this can fire twice for the
  # same event. Check-before-write (or rely on a unique constraint) so
  # the second delivery is a no-op.
  def handle(%UserRegistered{user_id: id, email: email, name: name}, _meta) do
    case MyApp.Repo.get_by(EmailLog, user_id: id, type: "welcome") do
      nil ->
        MyApp.Mailer.send_welcome(email, name)
        MyApp.Repo.insert!(%EmailLog{user_id: id, type: "welcome"})
        :ok

      _already_sent ->
        :ok
    end
  end
end
```

**Rule:** Event handlers must be idempotent — Commanded delivers at-least-once, and replaying handlers (e.g., during a reset) re-fires every event. Many handlers are naturally idempotent (upserts, `Repo.insert(..., on_conflict: :nothing)`, projections via `Ecto.Multi`). Side-effecting handlers (email, webhook) need explicit deduplication.

### Dispatch

```elixir
# Eventual consistency (default — fastest)
:ok = MyApp.Router.dispatch(%RegisterUser{user_id: id, email: email, name: name})

# Strong consistency — block until all :strong handlers complete
:ok = MyApp.Router.dispatch(cmd, consistency: :strong)

# Strong against specific handlers only (best of both worlds)
:ok = MyApp.Router.dispatch(cmd, consistency: [MyApp.Accounts.Projections.UserProjection])

# With timeout and metadata
:ok = MyApp.Router.dispatch(cmd,
  consistency: :strong,
  timeout: 10_000,
  metadata: %{user_id: current_user.id, request_id: req_id}
)
```

## Anti-patterns

### Don't: query the database inside `execute/2` or `apply/2`

```elixir
# BAD
def execute(state, %RegisterUser{email: email} = cmd) do
  if MyApp.Repo.exists?(from u in User, where: u.email == ^email) do
    {:error, :email_taken}
  else
    %UserRegistered{...}
  end
end
```

**Why it bites:** Aggregates replay from events on cold load. If `execute/2` (or `apply/2`) reads from the DB, replay gives different answers than the original dispatch did, and your aggregate state becomes non-deterministic. Worse, the read model may not yet exist during replay.

**Instead:** Enforce uniqueness via a separate "unique constraint" aggregate, a process manager that reserves the email before allowing registration, or accept the race and reject duplicates at the projection layer with a unique index.

### Don't: put business logic in event handlers

```elixir
# BAD
def handle(%OrderPlaced{} = ev, _meta) do
  if ev.total > 1000 do
    MyApp.Router.dispatch(%FlagForReview{order_id: ev.order_id})
  end
end
```

**Why it bites:** Business rules should be enforceable on replay. An event handler runs once per event delivery; if you rebuild projections, this dispatch *runs again* (or doesn't, depending on handler reset). Logic in handlers is invisible to the aggregate's invariants.

**Instead:** Use a Process Manager. Its state is persisted, its dispatches are tracked, and its `interested?/1` + `handle/2` shape make the workflow auditable.

### Don't: dispatch commands from inside `execute/2`

```elixir
# BAD
def execute(state, %TransferFunds{} = cmd) do
  MyApp.Router.dispatch(%DebitAccount{account_id: cmd.from, amount: cmd.amount})
  MyApp.Router.dispatch(%CreditAccount{account_id: cmd.to, amount: cmd.amount})
  %TransferInitiated{...}
end
```

**Why it bites:** Aggregates must be pure. Dispatching from inside `execute/2` couples aggregates to each other, defeats replay purity, and creates cycles where one aggregate's command can recursively trigger itself.

**Instead:** Aggregate emits `TransferInitiated`. A Process Manager subscribes, and IT dispatches `DebitAccount` and `CreditAccount`, listening for confirmations or compensating events.

### Don't: change event field semantics or rename fields

```elixir
# BAD — field reuse
defmodule UserRegistered do
  defstruct [:user_id, :email]   # was previously :user_email
end
```

**Why it bites:** Old events in the store still have the old field name (or different semantics under the same name). Replay deserializes them and your `apply/2` gets unexpected shapes. Production crashes on every cold start.

**Instead:** Add a new field (default nil), or define `UserRegisteredV2` and write an upcaster (see `references/event-versioning.md`) that converts V1 events to V2 on read. Never mutate event semantics in place.

### Don't: read your own writes synchronously without `:strong` consistency

```elixir
# BAD
:ok = MyApp.Router.dispatch(%RegisterUser{user_id: id, ...})
user = MyApp.Repo.get(User, id)   # may be nil — projection hasn't caught up
```

**Why it bites:** Default consistency is `:eventual`. The dispatch returns when the event is persisted, but the projection that writes to the read model runs asynchronously. You'll see flaky tests and intermittent nils in production.

**Instead:** Use `consistency: :strong` (or `consistency: [SpecificProjection]`) when you need read-after-write semantics. Accept the latency cost. For most flows (background jobs, async UI updates), eventual is fine and faster.

## Common Gotchas

- **Aggregates spawn lazily and idle out** — Commanded starts an aggregate process on first dispatch, hydrates state from the event store, then idles per the configured lifespan. Cold starts pay the replay cost; hot aggregates don't.
- **Snapshots break on state shape changes** — bump `@snapshot_version` whenever the aggregate struct changes. Old snapshots are discarded and the aggregate replays from events.
- **Event handlers must be idempotent** — Commanded retries failed handlers, and at-least-once delivery means the same event can be processed twice. Use unique constraints, idempotency keys, or check-before-write logic.
- **`:strong` consistency only blocks on handlers explicitly marked `:strong`** — declaring `consistency: :strong` on the dispatch doesn't promote `:eventual` handlers. Both ends must agree:
  ```elixir
  # Handler side — declare strong on the use macro
  use Commanded.Projections.Ecto, consistency: :strong

  # Dispatch side — request strong
  MyApp.Router.dispatch(cmd, consistency: :strong)
  ```
  If only one side declares it, the dispatch returns before this handler completes.
- **Process Manager state persists indefinitely unless you complete it** — return `:stop` from `handle/2` to tear down. Otherwise zombie process managers accumulate forever.
- **Subscription names must be globally unique within the application** — duplicates cause one handler to silently never fire. The `name:` option is the subscription identifier in the event store.
- **`identify` `prefix:` matters for stream naming** — changing the prefix orphans existing streams. Pick the convention up front and keep it.
- **`@derive Jason.Encoder` on every event struct** — without it, events fail to serialize and dispatch crashes. Easy to forget on new events. Consider a `use MyApp.Event` macro that wraps it.

## Quick Reference

```
Aggregate callbacks:
  execute(state, command)  →  event | [events] | {:error, reason} | nil
  apply(state, event)      →  new_state

Process Manager callbacks:
  interested?(event)  →  {:start, id} | {:continue, id} | {:stop, id} | false
  handle(state, event) →  command | [commands] | {:error, reason} | []
  apply(state, event)  →  new_state | {:stop, state}
  error(error, command, context) → :skip | {:retry, ms} | {:stop, reason}

Event Handler callback:
  handle(event, metadata)  →  :ok | {:error, reason}

Consistency modes (dispatch):
  :eventual              — default, async, fastest
  :strong                — block on ALL :strong handlers
  [Handler1, Handler2]   — block on these specific handlers only
```

## When to Load Deeper References

- Designing event versioning, upcasters, or migrating event schemas? → Read `references/event-versioning.md`
- Implementing a saga with compensation, complex state machines, or timeout-driven steps in a process manager? → Read `references/process-managers.md`
- Configuring snapshots, lifespan, or aggregate performance tuning? → Read `references/aggregate-tuning.md`
- Writing custom Commanded middleware (auth, multi-tenancy, audit logging)? → Read `references/middleware.md`
- Testing aggregates, projections, and process managers (Commanded.Aggregate.Multi, EventStore test helpers)? → Read `references/testing.md`
