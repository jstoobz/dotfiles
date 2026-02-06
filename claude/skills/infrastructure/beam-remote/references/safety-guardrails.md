# Safety Guardrails for Live BEAM Nodes

## Core Principle

**Read-only by default.** Never execute mutations on a live node without explicit user confirmation.

## Full Classification

### SAFE — Auto-allowed (read-only inspection)

```elixir
# System info
:erlang.memory()
:erlang.system_info(:process_count)
:erlang.system_info(:process_limit)
:erlang.system_info(:port_count)
:erlang.system_info(:port_limit)
:erlang.system_info(:scheduler_count)
:erlang.system_info(:otp_release)
:erlang.statistics(:run_queue_lengths)

# Process inspection
Process.list()
Process.info(pid)
Process.info(pid, :memory)
Process.whereis(name)

# GenServer state (read-only)
:sys.get_state(pid_or_name)

# Recon (all read-only)
:recon.proc_count(attribute, n)
:recon.proc_window(attribute, n, milliseconds)
:recon.bin_leak(n)
:recon.scheduler_usage(milliseconds)
:recon.info(pid)
:recon.info(pid, key)

# ETS inspection
:ets.all()
:ets.info(table)
:ets.info(table, key)
:ets.tab2list(table)  # CAUTION if table is large

# Ecto SELECT queries
MyApp.Repo.all(query)
MyApp.Repo.one(query)
MyApp.Repo.aggregate(query, :count)

# Application config
Application.get_env(:my_app, key)
Application.get_all_env(:my_app)
```

### CAUTION — Warn user, proceed if acknowledged

```elixir
# Garbage collection (can cause brief pauses)
:erlang.garbage_collect(pid)
:erlang.processes() |> Enum.each(&:erlang.garbage_collect/1)

# Tracing (can impact performance if misconfigured)
:sys.trace(pid, true)
:recon_trace.calls({mod, fun, args}, max_calls)

# System flags (changes VM behavior)
:erlang.system_flag(:scheduler_wall_time, true)
```

**Warn template:**

> "This operation has side effects: [description]. It's generally safe but may briefly impact performance. Proceed?"

### DANGEROUS — Block and require explicit confirmation

```elixir
# Data mutations
MyApp.Repo.insert(changeset)
MyApp.Repo.update(changeset)
MyApp.Repo.delete(record)
MyApp.Repo.delete_all(query)
Ecto.Multi.* |> MyApp.Repo.transaction()

# Commanded dispatch (if using CQRS)
MyApp.Domain.dispatch(command)

# Process control
Process.exit(pid, reason)
GenServer.cast(pid, message)
GenServer.call(pid, message)  # Can have side effects
send(pid, message)

# Node/system control
:init.stop()
:erlang.halt()
System.stop()
Node.stop()

# Oban mutations
Oban.cancel_job(id)
Oban.cancel_all_jobs(query)
Oban.retry_job(id)
Oban.retry_all_jobs(query)
Oban.drain_queue(queue: name)

# Application control
Application.stop(:my_app)
Supervisor.terminate_child(sup, child)
Supervisor.restart_child(sup, child)
```

**Block template:**

> "MUTATION DETECTED: This command would [description of effect] on the live [env] node. This action [is/is not] reversible.
>
> To proceed, please confirm: 'Yes, [action description] on [env]'"

## Emergency Procedures

### When to disconnect immediately

- Node becomes unresponsive after a command
- Memory spikes dramatically after an operation
- You accidentally started a mutation — disconnect does NOT roll it back

### How to disconnect safely

1. `Ctrl+C` twice (detaches from remote console)
2. `exit` (leaves the bash session)
3. The node continues running — your session is just detached

### What NOT to do

- Never run `:init.stop()` or `:erlang.halt()` (kills the node)
- Never force-kill processes you don't understand
- Never run `Enum.each(Process.list(), &Process.exit(&1, :kill))` (kills everything)
- Never run unbounded queries without `|> Enum.take(N)` (can OOM the node)
- Never run `:recon_trace.calls/2` without a call limit (floods console)
