# Supervision Trees Reference

## Basic Supervisor

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Static children — started in order, stopped in reverse
      {MyApp.Repo, []},
      {Phoenix.PubSub, name: MyApp.PubSub},
      {MyApp.Cache, ttl: :timer.minutes(15)},
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      MyAppWeb.Endpoint
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Strategy Decision Guide

### :one_for_one (Default)

```
Children are independent. Restart only the failed child.
Use when: Most cases. Workers don't depend on each other.

[A] [B] [C]
      ↓ B crashes
[A] [B'] [C]   ← only B restarted
```

### :one_for_all

```
All children are interdependent. Restart all if one fails.
Use when: Children share state or must be in sync (e.g., producer + consumer).

[A] [B] [C]
      ↓ B crashes
[A'] [B'] [C']  ← all restarted
```

### :rest_for_one

```
Later children depend on earlier ones. Restart failed + all after it.
Use when: Ordered dependencies (e.g., DB → Cache → API).

[A] [B] [C]
      ↓ B crashes
[A] [B'] [C']   ← B and C restarted, A untouched
```

## DynamicSupervisor

```elixir
defmodule MyApp.WorkerSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
  end

  # Start workers on demand
  def start_worker(args) do
    spec = {MyApp.Worker, args}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  # Stop a specific worker
  def stop_worker(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  # Count active workers
  def count do
    DynamicSupervisor.count_children(__MODULE__)
  end
end
```

## Registry

### Unique Registry (Name Lookup)

```elixir
# In supervision tree
{Registry, keys: :unique, name: MyApp.WorkerRegistry}

# Worker registration
defmodule MyApp.Worker do
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  def get(id), do: GenServer.call(via(id), :get)

  defp via(id), do: {:via, Registry, {MyApp.WorkerRegistry, id}}
end

# Lookup
case Registry.lookup(MyApp.WorkerRegistry, "worker-123") do
  [{pid, _value}] -> {:ok, pid}
  [] -> {:error, :not_found}
end
```

### Duplicate Registry (PubSub)

```elixir
# In supervision tree
{Registry, keys: :duplicate, name: MyApp.EventRegistry}

# Subscribe
Registry.register(MyApp.EventRegistry, "user:created", [])

# Broadcast
Registry.dispatch(MyApp.EventRegistry, "user:created", fn entries ->
  for {pid, _} <- entries, do: send(pid, {:event, "user:created", payload})
end)
```

## Child Spec Customization

```elixir
# Default child_spec (from use GenServer)
def child_spec(arg) do
  %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [arg]},
    restart: :permanent,
    type: :worker
  }
end

# Restart strategies:
# :permanent — always restart (default for GenServer)
# :temporary — never restart (one-shot tasks)
# :transient — restart only on abnormal exit (Oban workers)

# Override in module
use GenServer, restart: :transient

# Override in supervisor
children = [
  %{id: MyWorker, start: {MyWorker, :start_link, []}, restart: :temporary}
]
```

## Tree Design Patterns

### Application Tree (typical)

```
Application.Supervisor (:one_for_one)
├── Repo
├── PubSub
├── Telemetry
├── Domain.Supervisor (:rest_for_one)
│   ├── EventStore (if using Commanded)
│   ├── Domain (Commanded application)
│   └── ProjectorSupervisor
├── WorkerSupervisor (DynamicSupervisor)
├── Oban
└── Endpoint
```

### Context Supervisor

```elixir
defmodule MyApp.Accounts.Supervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      MyApp.Accounts.Cache,
      {Task.Supervisor, name: MyApp.Accounts.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Shutdown Order

```
# Children are stopped in REVERSE start order
# This ensures dependencies are still available during shutdown

# Start order:  Repo → Cache → API → Endpoint
# Stop order:   Endpoint → API → Cache → Repo

# Shutdown timeout per child (default: 5000ms)
%{id: MyWorker, start: {MyWorker, :start_link, []}, shutdown: 10_000}

# For supervisors, use :infinity to allow children to shut down
%{id: MySup, start: {MySup, :start_link, []}, type: :supervisor, shutdown: :infinity}
```
