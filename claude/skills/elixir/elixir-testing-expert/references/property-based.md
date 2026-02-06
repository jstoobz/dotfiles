# Property-Based Testing Reference

## StreamData Basics

```elixir
defmodule MyApp.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Basic property test
  property "reversing a list twice gives the original" do
    check all list <- list_of(integer()) do
      assert list == list |> Enum.reverse() |> Enum.reverse()
    end
  end

  # With size limit
  property "sorting is idempotent" do
    check all list <- list_of(integer(), max_length: 100) do
      sorted = Enum.sort(list)
      assert sorted == Enum.sort(sorted)
    end
  end
end
```

## Built-in Generators

```elixir
# Primitives
integer()                    # Any integer
positive_integer()           # > 0
float()                      # Any float
boolean()                    # true/false
binary()                     # Random binary
string(:alphanumeric)        # Letters and digits
string(:ascii)               # ASCII characters
atom(:alphanumeric)          # Random atoms

# Collections
list_of(integer())                    # List of ints
list_of(integer(), min_length: 1)     # Non-empty
list_of(integer(), max_length: 10)    # Bounded
map_of(string(:alphanumeric), integer())  # Map
keyword_of(integer())                 # Keyword list

# Combinators
one_of([integer(), string(:alphanumeric)])  # Pick one generator
member_of([:admin, :member, :viewer])       # Pick from list
constant(42)                                # Always 42
frequency([{3, :ok}, {1, :error}])          # Weighted random
```

## Custom Generators

```elixir
# Email generator
def email_gen do
  gen all name <- string(:alphanumeric, min_length: 1, max_length: 20),
          domain <- member_of(["example.com", "test.org", "mail.net"]) do
    "#{String.downcase(name)}@#{domain}"
  end
end

# Money generator (Decimal)
def money_gen(min \\ 0, max \\ 10_000) do
  gen all cents <- integer(min * 100..max * 100) do
    Decimal.div(Decimal.new(cents), 100)
  end
end

# Date range generator
def date_gen(start_year \\ 2020, end_year \\ 2025) do
  gen all year <- integer(start_year..end_year),
          month <- integer(1..12),
          day <- integer(1..28) do  # 28 to avoid invalid dates
    Date.new!(year, month, day)
  end
end

# User struct generator
def user_gen do
  gen all email <- email_gen(),
          name <- string(:alphanumeric, min_length: 2, max_length: 50),
          role <- member_of([:admin, :member, :viewer]),
          active <- boolean() do
    %User{email: email, name: name, role: role, active: active}
  end
end
```

## Domain-Specific Generators

```elixir
# Domain-specific generators
def policy_status_gen do
  member_of([:draft, :active, :expired, :cancelled, :archived])
end

def coverage_amount_gen do
  gen all dollars <- integer(1_000..1_000_000),
          cents <- integer(0..99) do
    Decimal.new("#{dollars}.#{String.pad_leading(to_string(cents), 2, "0")}")
  end
end

def category_gen do
  member_of([:occ_acc, :cargo, :general_liability, :auto])
end
```

## Property Test Patterns

### Roundtrip (Encode/Decode)

```elixir
property "JSON roundtrip preserves data" do
  check all data <- map_of(string(:alphanumeric), one_of([integer(), string(:ascii)])) do
    assert {:ok, decoded} = data |> Jason.encode!() |> Jason.decode()
    assert decoded == data
  end
end
```

### Invariant Preservation

```elixir
property "changeset always validates email format" do
  check all email <- string(:alphanumeric, min_length: 1) do
    # Emails without @ should always fail validation
    changeset = User.changeset(%User{}, %{email: email, name: "Test"})
    refute changeset.valid?
    assert %{email: [_]} = errors_on(changeset)
  end
end
```

### Commutativity

```elixir
property "order of filters doesn't matter" do
  check all role <- member_of([:admin, :member]),
            active <- boolean() do
    result1 = User |> by_role(role) |> by_active(active) |> Repo.all()
    result2 = User |> by_active(active) |> by_role(role) |> Repo.all()
    assert MapSet.new(result1, & &1.id) == MapSet.new(result2, & &1.id)
  end
end
```

### No Crash (Robustness)

```elixir
property "parser never crashes on arbitrary input" do
  check all input <- string(:ascii, max_length: 1000) do
    # Should return {:ok, _} or {:error, _}, never crash
    result = MyApp.Parser.parse(input)
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end
end
```

## Shrinking

StreamData automatically shrinks failing cases to minimal examples:

```elixir
# If this fails for [100, -50, 75, -25, 30]
# StreamData will try to find the simplest failing case
# e.g., [1, -1] or [-1]
property "sum of absolute values >= sum" do
  check all list <- list_of(integer(), min_length: 1) do
    abs_sum = list |> Enum.map(&abs/1) |> Enum.sum()
    assert abs_sum >= Enum.sum(list)
  end
end
```

## Integration with ExUnit

```elixir
# Control iterations
property "expensive property", max_runs: 50 do
  check all data <- expensive_gen(), max_runs: 50 do
    assert valid?(data)
  end
end

# Seed for reproducibility (shown in failure output)
# mix test --seed 12345
```
