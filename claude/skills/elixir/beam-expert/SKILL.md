---
name: beam-expert
description: BEAM VM and OTP runtime patterns — processes, GenServer, supervision, Registry, ETS, persistent_term, atomics, and production debugging
targets:
  elixir: "1.18+"
  otp: "27+"
---

# BEAM/OTP Expert

## When to Use This Skill

- Designing process structure: GenServer, Task, Agent, DynamicSupervisor, Registry
- Choosing between concurrency primitives or coordination strategies
- Picking shared-state mechanisms (ETS, `:persistent_term`, `:counters`, `:atomics`, Agent)
- Diagnosing production issues: memory leaks, message-queue growth, scheduler hot spots
- Working with `:sys`, `:recon`, `:observer`, or `Process.info/2` for live inspection
- **Skip this skill when working on Elixir language idioms (pattern matching, `with` chains, pipelines, error tuples) — use `elixir-expert`. Skip for app/web architecture — use `phoenix-expert`.**

## Mental Model

- **Lightweight processes** — not OS threads. Millions are normal, ~2KB each.
- **Share nothing** — processes communicate only via messages, which are *copied* (not shared by reference). Big messages = expensive sends.
- **Preemptive scheduling** — fair CPU via reduction counting. No process can starve others; even tight loops yield.
- **Let it crash** — processes are isolated. Crashes are handled by supervisors, not by defensive `try/rescue` in business logic.
- **Soft real-time** — designed for predictable latency under sustained load, not maximum throughput.

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
│   ├── Compile-time-immutable, read by many? → :persistent_term (no copy on read)
│   ├── Counters / atomic increments? → :counters or :atomics (lock-free)
│   ├── Small, low contention? → Agent
│   └── Large or read-heavy mutable? → ETS (:public for many writers)
├── State machine with explicit transitions? → :gen_statem (or GenStateMachine)
├── Backpressure / demand-driven pipeline? → GenStage / Flow / Broadway
├── Periodic work?
│   ├── Lost on restart OK? → :timer.send_interval / Process.send_after
│   └── Must survive restart? → Oban (see oban-expert)
└── Long-running cross-aggregate workflow? → Process Manager (see commanded-expert)
```

## Decision Tree: Shared State Mechanism

```
What's the access pattern?
├── Read-only after write, written rarely (config, lookup tables)? → :persistent_term
│   └── WARNING: every write triggers global GC — write at boot, never per-request
├── Atomic counters / read-modify-write integers? → :counters (or :atomics for full array)
├── Mutable map of small data, mostly reads? → ETS :set with read_concurrency: true
├── Mutable map written from one process? → Agent or GenServer state
├── Mutable map written from many processes? → ETS :public + careful single-op writes
├── Need ordered iteration / range queries? → ETS :ordered_set
├── Distributed across nodes? → :mnesia or :pg / Phoenix.PubSub
└── Just process-local state? → GenServer state (don't reach for ETS by default)
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
├── Just want notification on crash? → Monitor (Process.monitor)
│   └── Receive {:DOWN, ref, :process, pid, reason}
└── Supervisor manages lifecycle? → Link (automatic via child_spec)
```

## Core Patterns

### GenServer essentials

```elixir
defmodule MyApp.Worker do
  use GenServer

  # Client API — runs in the caller's process
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def get(key), do: GenServer.call(__MODULE__, {:get, key})
  def put(key, val), do: GenServer.cast(__MODULE__, {:put, key, val})

  # Server callbacks — run in the GenServer process
  @impl true
  def init(opts) do
    Process.set_label({:worker, opts[:tag]})  # visible in :observer / :recon
    {:ok, %{}, {:continue, :hydrate}}
  end

  @impl true
  def handle_continue(:hydrate, state) do
    # Heavy initialization runs here, AFTER init returns. Boot stays fast.
    {:noreply, load_state(state)}
  end

  @impl true
  def handle_call({:get, key}, _from, state), do: {:reply, Map.get(state, key), state}

  @impl true
  def handle_cast({:put, key, val}, state), do: {:noreply, Map.put(state, key, val)}

  @impl true
  def handle_info(:cleanup, state), do: {:noreply, do_cleanup(state)}

  defp load_state(state), do: state
  defp do_cleanup(state), do: state
end
```

**Rule:** Heavy work belongs in `handle_continue/2`, not `init/1`. `init/1` blocks the supervisor; `handle_continue` runs after init returns and before any other message is processed.

**Return value cheatsheet:**
- `handle_call` → `{:reply, response, new_state}` | `{:noreply, new_state}` | `{:stop, reason, response, state}`
- `handle_cast/info` → `{:noreply, new_state}` | `{:stop, reason, state}`
- Add `timeout` (ms) or `:hibernate` as 4th element to optimize idle behavior

### `:persistent_term` for read-heavy compile-time data

```elixir
# At app boot — write ONCE, then read many
:persistent_term.put({MyApp, :feature_flags}, %{new_ui: true, beta: false})

# Hot path — zero-copy read, no message passing
def feature_enabled?(flag) do
  :persistent_term.get({MyApp, :feature_flags}, %{})[flag] || false
end

# NEVER in a request handler — this triggers global GC of every reader process:
# :persistent_term.put({MyApp, :feature_flags}, new_flags)  # ❌
```

**Rule:** `:persistent_term` is the right choice when reads vastly outnumber writes. Writing triggers a global GC of every process that has read the term — fine at boot, catastrophic per-request. Use namespaced tuple keys (`{MyApp, :name}`) to avoid global collisions.

### `:counters` / `:atomics` for lock-free counts

```elixir
# Allocate at boot, share the ref
ref = :counters.new(3, [:atomics])
Application.put_env(:my_app, :request_counter, ref)

# Hot path — true lock-free atomic increment
def record_request(status) do
  idx = case status do
    :ok -> 1
    :error -> 2
    :timeout -> 3
  end

  :counters.add(Application.fetch_env!(:my_app, :request_counter), idx, 1)
end

# Read snapshot
:counters.get(ref, 1)
```

**Rule:** `:counters` (and `:atomics`) operate on fixed-size integer arrays with hardware atomics. Far cheaper than ETS for high-frequency counts. No process; no message passing.

### ETS quick reference

```
Table types:
├── :set            — unique keys, one value (default)
├── :ordered_set    — sorted by key (range queries, ordered iteration)
├── :bag            — multiple values per key, unique tuples
└── :duplicate_bag  — allows identical tuples

Access modes:
├── :public         — any process reads/writes
├── :protected      — owner writes, all read (default)
└── :private        — only owner

Performance flags:
├── read_concurrency: true   — optimize for many concurrent readers
├── write_concurrency: true  — finer-grained locks for many writers
└── decentralized_counters: true (OTP 23+) — better counter scalability
```

```elixir
# Typical setup — owned by a GenServer, read by anyone
table = :ets.new(:my_cache, [:set, :public, :named_table,
                             read_concurrency: true,
                             write_concurrency: true])

:ets.insert(table, {key, value})
:ets.lookup(table, key)              # [{key, value}] or []
:ets.match_object(table, {:_, val})  # all entries with that value
```

### Production debugging primitives

```elixir
# Top memory consumers
:recon.proc_count(:memory, 10)

# Top message queue lengths (growing = problem)
:recon.proc_count(:message_queue_len, 10)

# Inspect GenServer state
:sys.get_state(pid_or_name)

# Trace messages (use sparingly in prod — verbose)
:sys.trace(pid, true)
:sys.trace(pid, false)

# Process info — pick what you need, full info is expensive
Process.info(pid, [:message_queue_len, :memory, :current_function, :status])

# All registered names
Process.registered()

# Label a process so it's identifiable in :observer / :recon (since 1.17)
Process.set_label({:worker, :primary})

# Find a process by label
Process.list() |> Enum.filter(&(Process.info(&1, :label) == {:label, {:worker, :primary}}))
```

## Anti-patterns

### Don't: do heavy work in `init/1`

```elixir
# BAD
def init(opts) do
  data = MyApp.HeavyLoader.load_everything()  # 30 seconds
  {:ok, %{data: data}}
end
```

**Why it bites:** `init/1` blocks the supervisor. If it takes longer than the supervisor's `:timeout` (typically 5s), the supervisor kills the child and retries — possibly forever. The whole supervision tree above is also blocked from coming up.

**Instead:**

```elixir
# GOOD
def init(opts), do: {:ok, %{data: nil}, {:continue, :load}}

def handle_continue(:load, state) do
  data = MyApp.HeavyLoader.load_everything()
  {:noreply, %{state | data: data}}
end
```

`handle_continue/2` runs after `init/1` returns but before any other message — supervisor unblocks immediately, your process is "ready" once the continue completes.

### Don't: store giant terms in messages between processes

```elixir
# BAD
GenServer.call(server, {:process, huge_binary_or_map})  # term is COPIED into mailbox
```

**Why it bites:** Sends copy the entire term to the recipient's heap. A 100MB map sent to 10 workers allocates 1GB. The garbage of those copies stays around until each receiver GCs.

**Instead:** Put large data in ETS (or `:persistent_term` if read-only), pass a reference/key. Or pass a function that the receiver calls when needed (closures don't capture by value).

### Don't: use Agent for high-contention shared state

```elixir
# BAD
Agent.start_link(fn -> %{} end, name: MyCache)
# 1000 concurrent writers all serialize through the Agent process
```

**Why it bites:** Agent is a single GenServer. Every read AND write serializes through one mailbox. Under contention, the Agent becomes the bottleneck and its mailbox grows unbounded.

**Instead:** ETS with `:public + write_concurrency: true` for many-writer mutable state, `:counters` for atomic increments, or `:persistent_term` for read-heavy immutable.

### Don't: use the process dictionary for state

```elixir
# BAD
def cache_user(user) do
  Process.put({:user, user.id}, user)
end

def get_user(id) do
  Process.get({:user, id})
end
```

**Why it bites:** Process dictionary is invisible in your function signature, untestable in isolation, and ties your code to whichever process happens to be executing. Refactors that change which process runs the code silently break.

**Instead:** Pass state explicitly through function arguments, or store in ETS with explicit ownership. The few legitimate uses of the process dictionary (Logger metadata, Phoenix conn assigns) are infrastructure — not application state.

### Don't: catch `EXIT` signals when you mean to handle errors

```elixir
# BAD
def perform do
  Process.flag(:trap_exit, true)
  task = Task.async(fn -> risky_work() end)
  receive do
    {:EXIT, _, reason} -> {:error, reason}
  end
end
```

**Why it bites:** `trap_exit` changes how this process handles ALL exits, including from its supervisor. You're now responsible for orderly shutdown. And `risky_work` raising an exception doesn't send `:EXIT` — it sends a Task `{ref, result}` reply or kills the linked task.

**Instead:** Use `try/rescue` for exceptions, `Task.async + Task.await` for results, and only set `trap_exit` when you're explicitly building a supervisor or supervised long-lived process.

## Common Gotchas

- **`erlang:phash2` over maps with >32 keys is unstable** — Maps switch internal representation from sorted `flat_map` to HAMT once they exceed 32 keys. `phash2` hashes the term representation, so two logically-equal maps can produce different hashes if one has ≤32 keys and the other has >32. Burns hashing pipelines that compare structural snapshots. If you need stable hashing of maps that may grow, normalize the structure first: `map |> Map.to_list() |> Enum.sort() |> :erlang.phash2()`.
- **`Process.send/3` to a dead pid silently succeeds** — sends to dead processes return `:ok` and the message is dropped. Use `Process.alive?/1` only as a hint (TOCTOU race), or use `Process.monitor/1` for real "is it gone" semantics.
- **Mailbox growth is your responsibility** — there's no built-in backpressure on `send/2`. A slow receiver with fast senders accumulates messages until OOM. Use `GenStage`/`Broadway` for demand-driven flow, or selective receive + drop policy.
- **`:hibernate` is not free** — returning `{:noreply, state, :hibernate}` releases the process heap, but the next message triggers a full GC and heap reallocation. Worth it for processes idle for minutes; counterproductive for processes idle for milliseconds.
- **ETS `:public` writes from many processes have no multi-op atomicity** — single operations (`insert`, `update_counter`) are atomic, but `lookup + insert` is not. Use `:ets.update_counter/3` for atomic increments, `:ets.insert_new/2` for "insert if absent", or guard multi-step writes through a single GenServer.
- **`:persistent_term` writes trigger global GC** — every process that has ever read the term gets GC'd on every write. Write at boot or on rare config changes; never per-request.
- **Linked process crash propagates synchronously** — when a linked process exits abnormally, your process receives an `:EXIT` signal that (without `trap_exit`) terminates yours immediately. Choose `link` vs `monitor` deliberately.
- **`Process.set_label/1` is debugger-visible only (OTP 27+)** — the label shows in `:observer` and `:recon`, but does NOT surface via `Process.info(pid, :label)` until future inspection hooks land. Use it for visual identification in debugging tools; don't build runtime lookup logic on top of it.
- **Registry vs `:global` vs `:pg` have different distribution semantics** — Registry is local-only (per-node), `:global` is cluster-wide but slow on conflict, `:pg` (process groups) is for many-to-many notification. Don't pick by name familiarity.

## Quick Reference

```
GenServer return shapes:
  init/1           → {:ok, state} | {:ok, state, timeout | :hibernate | {:continue, term}}
                   | {:stop, reason} | :ignore
  handle_call      → {:reply, reply, new_state, ...} | {:noreply, new_state, ...}
                   | {:stop, reason, reply, state} | {:stop, reason, state}
  handle_cast/info → {:noreply, new_state, ...} | {:stop, reason, state}
  handle_continue  → same as handle_cast
  terminate/2      → ignored (return value doesn't matter)

Common :recon recipes:
  :recon.proc_count(:memory, 10)              # top memory hogs
  :recon.proc_count(:message_queue_len, 10)   # mailbox bloat
  :recon.bin_leak(10)                         # binary leak suspects
  :recon.scheduler_usage(1000)                # scheduler load over 1s
  :recon_alloc.memory(:usage)                 # allocator efficiency

Process inspection (cheap):
  Process.info(pid, [:message_queue_len, :memory, :current_function, :status])
  :sys.get_state(pid)
  :sys.get_status(pid)         # includes module, parent, debug info
```

## When to Load Deeper References

- Designing a GenServer with timeout, hibernate, continue, terminate cleanup, or naming/registration patterns? → Read `references/genserver-patterns.md`
- Building a supervision tree with DynamicSupervisor, Registry, child_spec, or restart strategy decisions? → Read `references/supervision-trees.md`
- Debugging a production issue, tracking down a binary leak, profiling ETS hot spots, or running `:recon` recipes in detail? → Read `references/debugging-performance.md`
