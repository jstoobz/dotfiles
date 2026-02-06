# Debugging and Performance Reference

## Production Debugging with :recon

```elixir
# Top 10 processes by memory
:recon.proc_count(:memory, 10)
# Returns: [{pid, memory_bytes, [module, function, arity]}]

# Top 10 by message queue length (growing = bottleneck)
:recon.proc_count(:message_queue_len, 10)

# Top 10 by reductions (CPU usage proxy)
:recon.proc_count(:reductions, 10)

# Process info for specific pid
:recon.info(pid)
# Returns: current_function, initial_call, status, message_queue_len, etc.

# Scheduler utilization
:recon.scheduler_usage(1000)  # Sample for 1 second
# Returns: [{scheduler_id, usage_percentage}]

# Memory breakdown
:recon_alloc.memory(:allocated)
:recon_alloc.memory(:used)
```

## :sys Module (GenServer Debugging)

```elixir
# Get current state of a named GenServer
:sys.get_state(MyApp.Cache)
:sys.get_state(pid)

# Trace all messages (very verbose — use briefly)
:sys.trace(MyApp.Cache, true)
# Output: *DBG* ... handle_call, handle_cast, etc.
:sys.trace(MyApp.Cache, false)  # Turn off

# Get statistics
:sys.statistics(MyApp.Cache, true)   # Enable
:sys.statistics(MyApp.Cache, :get)   # Read
:sys.statistics(MyApp.Cache, false)  # Disable

# Suspend/resume (careful — blocks callers)
:sys.suspend(pid)
:sys.resume(pid)
```

## Process.info Diagnostics

```elixir
# Quick health check
Process.info(pid, [
  :message_queue_len,  # Should be near 0 under normal load
  :memory,             # Bytes used by process
  :current_function,   # What it's doing right now
  :status,             # :running, :waiting, :suspended
  :reductions,         # Work units performed
  :heap_size,          # Current heap size
  :total_heap_size,    # Heap + stack
  :garbage_collection  # GC stats
])

# Find registered process
Process.whereis(:my_server)

# List all registered names
Process.registered()
```

## Observer (Development)

```elixir
# GUI process inspector
:observer.start()

# Tabs:
# System   — scheduler load, memory, IO
# Load     — scheduler utilization over time
# Memory   — per-allocator breakdown
# Applications — supervision tree visualization
# Processes — sortable list of all processes
# Table Viewer — ETS table inspection
```

## ETS Performance Patterns

### Table Type Selection

```elixir
# :set — O(1) lookup, unique keys (most common)
:ets.new(:cache, [:set, :public, :named_table, read_concurrency: true])

# :ordered_set — O(log N) lookup, range queries possible
:ets.new(:sorted_cache, [:ordered_set, :named_table])

# Options for concurrent access:
# read_concurrency: true   — optimize for concurrent reads (slower writes)
# write_concurrency: true  — optimize for concurrent writes from different processes
# Both can be true for mixed workloads
```

### Common ETS Operations

```elixir
# Insert (overwrite if key exists for :set)
:ets.insert(:cache, {"key", value, System.monotonic_time()})

# Lookup
case :ets.lookup(:cache, "key") do
  [{_key, value, _ts}] -> {:ok, value}
  [] -> :miss
end

# Delete
:ets.delete(:cache, "key")

# Match with pattern
:ets.match(:cache, {:"$1", :"$2", :_})  # Returns [[key, value], ...]

# Select (more powerful than match)
:ets.select(:cache, [{{:"$1", :"$2", :"$3"}, [{:>, :"$3", min_ts}], [{{:"$1", :"$2"}}]}])

# Count entries
:ets.info(:cache, :size)

# Memory usage
:ets.info(:cache, :memory)  # In words (multiply by 8 for bytes on 64-bit)
```

### ETS as Cache with TTL

```elixir
defmodule MyApp.ETSCache do
  @table :my_cache
  @ttl_ms :timer.minutes(5)

  def init do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires}] when expires > System.monotonic_time(:millisecond) ->
        {:ok, value}
      _ ->
        :ets.delete(@table, key)  # Clean stale entry
        :miss
    end
  end

  def put(key, value) do
    expires = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {key, value, expires})
  end
end
```

## Memory Investigation

```elixir
# System-wide memory
:erlang.memory()
# Returns: [total: _, processes: _, system: _, atom: _, binary: _, ets: _]

# Process memory breakdown
Process.info(pid, :memory)

# Binary memory (shared heap — can be tricky)
# Large binaries (>64 bytes) are reference-counted on shared heap
# Sub-binaries reference parent — copy if you only need a small part
:erlang.garbage_collect(pid)  # Force GC to reclaim binary references

# Find processes holding large binaries
:recon.bin_leak(10)  # Top 10 processes by binary memory growth
```

## Common Performance Issues

### Message Queue Buildup

```
Symptom: Process memory growing, message_queue_len increasing
Cause: Producer faster than consumer
Fix:
1. Check :recon.proc_count(:message_queue_len, 10)
2. Identify the slow process
3. Options:
   - Speed up message handling
   - Add backpressure (GenStage)
   - Shard across multiple processes
   - Drop messages if acceptable
```

### Atom Table Exhaustion

```
Symptom: System crash with "atom table full"
Cause: Dynamic atom creation (String.to_atom with user input)
Fix: Use String.to_existing_atom/1 or keep strings as strings
Check: :erlang.system_info(:atom_count) / :erlang.system_info(:atom_limit)
```

### Large Binary Heap

```
Symptom: Memory growing despite low process count
Cause: Reference-counted binaries not being GC'd
Fix:
1. :erlang.garbage_collect(pid) on suspected processes
2. Avoid sub-binary references to large binaries (copy instead)
3. Use :binary.copy/1 when extracting small parts of large binaries
```

### Scheduler Saturation

```
Symptom: High latency, schedulers at 100%
Cause: CPU-bound work on BEAM schedulers
Fix:
1. Check :recon.scheduler_usage(1000)
2. Move CPU-intensive work to dirty schedulers or NIFs
3. Break large computations into chunks with Process.sleep(0)
```
