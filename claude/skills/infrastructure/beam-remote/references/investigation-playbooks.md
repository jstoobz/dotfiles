# BEAM Investigation Playbooks

## Memory Investigation

### Step 1: Overview

```elixir
:erlang.memory()
|> Enum.map(fn {k, v} -> {k, Float.round(v / 1_048_576, 2)} end)
|> Enum.into(%{})
# Returns MB for: total, processes, binary, ets, atom, code, system
```

### Step 2: Top memory consumers

```elixir
:recon.proc_count(:memory, 10)
# Returns: [{pid, memory_bytes, [registered_name | initial_call]}]
```

### Step 3: Binary memory (common leak source)

```elixir
# Find processes holding refc binaries
:recon.bin_leak(10)

# Check binary memory before/after forced GC
before = :erlang.memory(:binary)
:erlang.processes() |> Enum.each(&:erlang.garbage_collect/1)
after_gc = :erlang.memory(:binary)
IO.puts("Freed: #{Float.round((before - after_gc) / 1_048_576, 2)} MB")
```

### Step 4: ETS table memory

```elixir
:ets.all()
|> Enum.map(fn table ->
  info = :ets.info(table)
  %{
    name: info[:name],
    size: info[:size],
    memory_bytes: info[:memory] * :erlang.system_info(:wordsize),
    type: info[:type],
    owner: info[:owner]
  }
end)
|> Enum.sort_by(& &1.memory_bytes, :desc)
|> Enum.take(20)
```

### Step 5: Process heap analysis

```elixir
# Find processes with huge heaps
for pid <- Process.list(),
    {:heap_size, size} = Process.info(pid, :heap_size),
    size > 1_000_000,
    do: {pid, size, Process.info(pid, :registered_name)}
```

## Process Investigation

### Step 1: Process count and limit

```elixir
length(Process.list())
:erlang.system_info(:process_limit)
```

### Step 2: Top processes by mailbox

```elixir
:recon.proc_count(:message_queue_len, 10)
# Any process with queue > 1000 is a red flag
```

### Step 3: Identify by initial call

```elixir
Process.list()
|> Enum.map(&Process.info(&1, :initial_call))
|> Enum.frequencies()
|> Enum.sort_by(&elem(&1, 1), :desc)
|> Enum.take(10)
```

### Step 4: Detailed process info

```elixir
# For a specific PID
Process.info(pid, [
  :registered_name, :initial_call, :current_function,
  :memory, :heap_size, :message_queue_len,
  :reductions, :status, :links
])
```

### Step 5: Find stuck processes

```elixir
# Processes in a specific function (possibly stuck)
for pid <- Process.list(),
    {:current_function, {m, f, a}} = Process.info(pid, :current_function),
    m == SomeModule,
    do: {pid, {m, f, a}}
```

## Scheduler Analysis

### Step 1: Check utilization

```elixir
# 5-second sample
:recon.scheduler_usage(5000)
# Returns list of {scheduler_id, utilization_percent}
# Sustained > 80% = CPU bound
```

### Step 2: Run queue lengths

```elixir
:erlang.statistics(:run_queue_lengths)
# Non-zero values indicate scheduler contention
```

### Step 3: Dirty schedulers

```elixir
:erlang.system_info(:dirty_cpu_schedulers)
:erlang.system_info(:dirty_io_schedulers)
```

## Recon Patterns Reference

### proc_count — Top N processes by attribute

```elixir
:recon.proc_count(:memory, N)
:recon.proc_count(:message_queue_len, N)
:recon.proc_count(:reductions, N)
:recon.proc_count(:heap_size, N)
```

### proc_window — Top N over a time window

```elixir
# Processes that grew the most in 10 seconds
:recon.proc_window(:memory, 10, 10_000)
```

### bin_leak — Processes holding binary references

```elixir
:recon.bin_leak(10)
```

### scheduler_usage — Scheduler utilization

```elixir
:recon.scheduler_usage(5000)  # 5-second sample
```

### info — Enhanced Process.info

```elixir
:recon.info(pid)
:recon.info(pid, :memory)
:recon.info(pid, [:memory, :message_queue_len, :current_function])
```

### get_state — GenServer state inspection

```elixir
# For named processes
:recon.get_state(MyApp.SomeServer)

# For registered names
:sys.get_state(Process.whereis(MyApp.SomeServer))
```

## GenServer State Inspection

```elixir
# By registered name
:sys.get_state(MyApp.SomeServer)

# By PID
:sys.get_state(pid)

# Get process info for a named process
Process.info(Process.whereis(MyApp.SomeServer))
```

## ETS Table Deep Dive

```elixir
# List all tables with details
:ets.all()
|> Enum.map(fn t -> {t, :ets.info(t)} end)

# Specific table contents (CAUTION: may be large)
:ets.tab2list(:some_table) |> Enum.take(10)

# Table size tracking (run multiple times)
:ets.info(:some_table, :size)
:ets.info(:some_table, :memory)
```

## Port/Socket Analysis

```elixir
# Total ports
length(Port.list())

# Port details
Port.list()
|> Enum.map(fn port ->
  info = Port.info(port)
  %{port: port, name: info[:name], connected: info[:connected]}
end)
```
