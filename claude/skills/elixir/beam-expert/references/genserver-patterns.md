# GenServer Patterns Reference

## Complete GenServer Template

```elixir
defmodule MyApp.Cache do
  use GenServer
  require Logger

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    ttl = Keyword.get(opts, :ttl, :timer.minutes(15))
    GenServer.start_link(__MODULE__, %{ttl: ttl}, name: name)
  end

  def get(key, server \\ __MODULE__) do
    GenServer.call(server, {:get, key})
  end

  def put(key, value, server \\ __MODULE__) do
    GenServer.cast(server, {:put, key, value})
  end

  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  # --- Server Callbacks ---

  @impl true
  def init(%{ttl: ttl} = config) do
    schedule_cleanup(ttl)
    {:ok, %{entries: %{}, config: config}}
  end

  @impl true
  def handle_call({:get, key}, _from, %{entries: entries} = state) do
    case Map.get(entries, key) do
      nil -> {:reply, nil, state}
      {value, _expires_at} -> {:reply, value, state}
    end
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | entries: %{}}}
  end

  @impl true
  def handle_cast({:put, key, value}, %{entries: entries, config: config} = state) do
    expires_at = System.monotonic_time(:millisecond) + config.ttl
    {:noreply, %{state | entries: Map.put(entries, key, {value, expires_at})}}
  end

  @impl true
  def handle_info(:cleanup, %{entries: entries, config: config} = state) do
    now = System.monotonic_time(:millisecond)
    cleaned = Map.reject(entries, fn {_k, {_v, expires}} -> expires < now end)
    schedule_cleanup(config.ttl)
    {:noreply, %{state | entries: cleaned}}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private ---

  defp schedule_cleanup(ttl) do
    Process.send_after(self(), :cleanup, ttl)
  end
end
```

## Timeout Pattern

```elixir
# GenServer hibernates after 5s of inactivity
@impl true
def init(state) do
  {:ok, state, 5_000}  # timeout in ms
end

@impl true
def handle_info(:timeout, state) do
  # Called when no message received within timeout
  {:noreply, cleanup(state), :hibernate}
end
```

## Hibernate Pattern

```elixir
# Hibernate reduces memory for idle processes (triggers full GC)
@impl true
def handle_call(:get, _from, state) do
  {:reply, state.value, state, :hibernate}
end

# Use for processes that are mostly idle
# Don't use for high-throughput processes (GC cost on wake)
```

## Continue Pattern

```elixir
# Continue allows multi-step init without blocking
@impl true
def init(opts) do
  {:ok, %{status: :loading}, {:continue, :load_data}}
end

@impl true
def handle_continue(:load_data, state) do
  data = expensive_load()
  {:noreply, %{state | status: :ready, data: data}}
end
```

## Naming Patterns

```elixir
# Module name (singleton)
GenServer.start_link(__MODULE__, arg, name: __MODULE__)

# Via Registry (dynamic, multiple instances)
def start_link(id) do
  GenServer.start_link(__MODULE__, id, name: via(id))
end

defp via(id), do: {:via, Registry, {MyApp.Registry, id}}

# Global (distributed)
GenServer.start_link(__MODULE__, arg, name: {:global, :my_service})
```

## Task Patterns

### Async/Await

```elixir
# Single task
task = Task.async(fn -> fetch_data() end)
result = Task.await(task, 10_000)  # 10s timeout

# Multiple tasks in parallel
tasks = Enum.map(urls, fn url ->
  Task.async(fn -> fetch(url) end)
end)
results = Task.await_many(tasks, 30_000)
```

### Task.async_stream (Parallel with Backpressure)

```elixir
# Process items in parallel, max 5 concurrent
items
|> Task.async_stream(&process/1, max_concurrency: 5, timeout: 30_000)
|> Enum.map(fn {:ok, result} -> result end)

# With ordered: false for faster completion
items
|> Task.async_stream(&process/1, max_concurrency: 10, ordered: false)
|> Enum.to_list()
```

### Supervised Tasks

```elixir
# Fire and forget (supervised, won't crash caller)
Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
  send_notification(user)
end)

# Async with supervisor (links to caller)
task = Task.Supervisor.async(MyApp.TaskSupervisor, fn ->
  fetch_external_data()
end)
result = Task.await(task)

# No-link async (caller survives task crash)
task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn ->
  risky_operation()
end)
case Task.yield(task, 5_000) || Task.shutdown(task) do
  {:ok, result} -> {:ok, result}
  {:exit, reason} -> {:error, reason}
  nil -> {:error, :timeout}
end
```

## Agent Patterns

```elixir
# Simple state container — use for small, low-contention state
{:ok, agent} = Agent.start_link(fn -> %{} end, name: MyApp.Settings)

# Read
Agent.get(MyApp.Settings, & &1)
Agent.get(MyApp.Settings, &Map.get(&1, :key))

# Write
Agent.update(MyApp.Settings, &Map.put(&1, :key, "value"))

# Read + Write atomically
Agent.get_and_update(MyApp.Settings, fn state ->
  {Map.get(state, :key), Map.put(state, :key, "new")}
end)

# For anything more complex, use GenServer instead
```

## Process Communication Patterns

```elixir
# Send and receive (rare — prefer GenServer)
send(pid, {:event, data})
receive do
  {:event, data} -> handle(data)
after
  5_000 -> :timeout
end

# Selective receive with assert_receive (tests)
send(self(), {:result, 42})
assert_receive {:result, value}
assert value == 42

# Monitor for cleanup
ref = Process.monitor(worker_pid)
receive do
  {:DOWN, ^ref, :process, _pid, reason} ->
    Logger.info("Worker stopped: #{inspect(reason)}")
end
```
