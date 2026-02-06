# Elixir Idioms Reference

## Pipeline Patterns

### Transform and Collect

```elixir
# Filter, transform, collect
orders
|> Enum.filter(&(&1.status == :pending))
|> Enum.map(&calculate_total/1)
|> Enum.sort_by(& &1.total, :desc)
|> Enum.take(10)
```

### Reduce for Aggregation

```elixir
# Build a map from a list
items
|> Enum.reduce(%{}, fn item, acc ->
  Map.update(acc, item.category, [item], &[item | &1])
end)

# Reduce with early exit
Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
  case validate(item) do
    {:ok, valid} -> {:cont, {:ok, [valid | acc]}}
    {:error, _} = err -> {:halt, err}
  end
end)
```

### Map with Index

```elixir
items
|> Enum.with_index(1)
|> Enum.map(fn {item, index} -> %{item | position: index} end)
```

## Comprehensions

### Basic

```elixir
# Equivalent to filter + map
for user <- users, user.active, do: user.email

# Multiple generators (cross-product)
for x <- 1..3, y <- 1..3, x != y, do: {x, y}

# Into a map
for {key, val} <- keyword_list, into: %{}, do: {key, String.upcase(val)}
```

### With Pattern Matching

```elixir
# Only process matching items
for {:ok, value} <- results, do: value

# Destructure maps
for %{name: name, age: age} <- users, age >= 18, do: name
```

## Recursive Patterns

### Tail-Recursive Accumulator

```elixir
def sum(list), do: sum(list, 0)
defp sum([], acc), do: acc
defp sum([head | tail], acc), do: sum(tail, acc + head)
```

### Process List with State

```elixir
def process_batch([], _state), do: :ok
def process_batch([item | rest], state) do
  new_state = handle_item(item, state)
  process_batch(rest, new_state)
end
```

## GenServer Client/Server Separation

```elixir
defmodule MyApp.Cache do
  use GenServer

  # --- Client API (called by other processes) ---
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get(key, server \\ __MODULE__) do
    GenServer.call(server, {:get, key})
  end

  def put(key, value, server \\ __MODULE__) do
    GenServer.cast(server, {:put, key, value})
  end

  # --- Server Callbacks (run in GenServer process) ---
  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end
end
```

## String Patterns

### Interpolation and Concatenation

```elixir
# Interpolation (preferred)
"Hello, #{name}!"

# Binary concatenation (for building)
first_name <> " " <> last_name

# IO Lists (efficient for building large strings)
[first_name, " ", last_name] |> IO.iodata_to_binary()
```

### Pattern Matching on Strings

```elixir
def parse_header("Bearer " <> token), do: {:ok, token}
def parse_header(_), do: {:error, :invalid_header}
```

## Map Patterns

### Map.merge vs Map.put

```elixir
# Single key
Map.put(map, :key, value)

# Multiple keys (merge wins)
Map.merge(defaults, overrides)

# Update existing key (raises if missing)
Map.update!(map, :count, &(&1 + 1))

# Update with default
Map.update(map, :count, 1, &(&1 + 1))
```

### Struct Update Syntax

```elixir
# Only works for structs, only updates existing fields
%User{user | name: "New Name", role: :admin}
```

## Keyword List Patterns

```elixir
# Options with defaults
def fetch(url, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 5_000)
  retries = Keyword.get(opts, :retries, 3)
  headers = Keyword.get(opts, :headers, [])
  # ...
end

# Validate required options
def connect(opts) do
  host = Keyword.fetch!(opts, :host)
  port = Keyword.get(opts, :port, 443)
  # ...
end
```

## Date/Time Patterns

```elixir
# Always use UTC
now = DateTime.utc_now()
today = Date.utc_today()

# Compare dates
Date.compare(date1, date2)  # :lt, :eq, :gt

# Add/subtract
Date.add(date, 30)  # 30 days later

# Never use NaiveDateTime for business logic
# Use DateTime with timezone or Date for date-only
```
