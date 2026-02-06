---
name: beam-expert
description: BEAM VM and OTP patterns including processes, GenServer, supervision, Registry, ETS, and production debugging
---

# BEAM/OTP Expert

## BEAM Mental Model

- **Lightweight processes**: Not OS threads — millions are normal, ~2KB each
- **Share nothing**: Processes communicate only via messages (copied, not shared)
- **Preemptive scheduling**: Fair CPU via reduction counting — no process can starve others
- **Let it crash**: Processes are isolated; crashes are handled by supervisors
- **Soft real-time**: Predictable latency, not maximum throughput

## Decision Tree: Concurrency Primitive

```
What do you need?
├── Synchronous request/response? → GenServer (handle_call)
├── Fire-and-forget message? → GenServer (handle_cast) or Task
├── One-off async work?
│   ├── Need result back? → Task.async/await
│   └── Don't need result? → Task.Supervisor.start_child
├── Parallel work + collect results? → Task.async_stream
├── Dynamic pool of workers? → DynamicSupervisor
├── Simple shared state?
│   ├── Small, low contention? → Agent
│   └── Large or read-heavy? → ETS
├── State machine with transitions? → :gen_statem (GenStateMachine)
├── Backpressure / demand-driven? → GenStage / Flow
├── Periodic work? → :timer.send_interval or Oban (if durable)
└── Long-running saga? → Process manager (Commanded) or GenServer
```

## Decision Tree: Supervision Strategy

```
How should children relate?
├── Independent (crash one, restart one)? → :one_for_one (most common)
├── All depend on each other? → :one_for_all
├── Ordered dependency (later depends on earlier)? → :rest_for_one
└── Workers created dynamically at runtime? → DynamicSupervisor
```

## Decision Tree: Links vs Monitors

```
Process relationship?
├── Must die together (parent-child)? → Link (spawn_link, start_link)
│   └── Parent wants to handle child crash? → Process.flag(:trap_exit, true)
├── Just want notification? → Monitor (Process.monitor)
│   └── Receive {:DOWN, ref, :process, pid, reason}
└── Supervisor manages lifecycle? → Link (automatic via child_spec)
```

## GenServer Essentials

```elixir
defmodule MyApp.Worker do
  use GenServer

  # Client API — runs in caller's process
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def get(key), do: GenServer.call(__MODULE__, {:get, key})
  def put(key, val), do: GenServer.cast(__MODULE__, {:put, key, val})

  # Server callbacks — runs in GenServer process
  @impl true
  def init(opts), do: {:ok, %{}}

  @impl true
  def handle_call({:get, key}, _from, state), do: {:reply, Map.get(state, key), state}

  @impl true
  def handle_cast({:put, key, val}, state), do: {:noreply, Map.put(state, key, val)}

  @impl true
  def handle_info(:cleanup, state), do: {:noreply, do_cleanup(state)}
end
```

**Return values:**

- `handle_call` → `{:reply, response, new_state}` | `{:noreply, new_state}` | `{:stop, reason, response, state}`
- `handle_cast/info` → `{:noreply, new_state}` | `{:stop, reason, state}`
- Add `timeout` or `:hibernate` as 4th element for idle optimization

## ETS Quick Reference

```
Table types:
├── :set         — unique keys, one value (default)
├── :ordered_set — sorted by key (range queries)
├── :bag         — multiple values per key, unique tuples
└── :duplicate_bag — allows identical tuples

Access:
├── :public      — any process reads/writes
├── :protected   — owner writes, all read (default)
└── :private     — only owner
```

## Debugging (Production)

```elixir
# Top memory consumers
:recon.proc_count(:memory, 10)

# Top message queue lengths (growing = problem)
:recon.proc_count(:message_queue_len, 10)

# Trace GenServer state
:sys.get_state(pid_or_name)

# Trace messages (careful in prod — verbose)
:sys.trace(pid, true)   # enable
:sys.trace(pid, false)  # disable

# Process info
Process.info(pid, [:message_queue_len, :memory, :current_function, :status])

# All registered names
Process.registered()
```

## References

- `references/genserver-patterns.md` — Full examples, timeout, hibernate, continue, naming
- `references/supervision-trees.md` — Tree design, DynamicSupervisor, Registry, child_spec
- `references/debugging-performance.md` — Production debugging, ETS patterns, :recon recipes
