---
name: elixir-expert
description: Core Elixir language patterns, idioms, and decision guidance for writing idiomatic functional code
---

# Elixir Expert

## Core Philosophy

- Immutability by default — data transforms through pipelines, never mutates
- Let it crash — design for recovery via supervision, not defensive coding
- Explicit over implicit — no magic, no hidden state
- Composition over inheritance — behaviours + protocols, not class hierarchies
- Small, pure functions composed via pipes

## Decision Tree: Data Structures

```
Need key-value data?
├── Fixed keys known at compile time? → Struct (enforce shape)
├── Dynamic/unknown keys? → Map
├── Ordered options/small config? → Keyword list
├── Need default values? → Keyword list with Keyword.get/3
└── Passing to Ecto/Phoenix? → Check what the API expects
```

## Decision Tree: Polymorphism

```
Need different behavior per data type?
├── Dispatching on data TYPE (struct)? → Protocol
│   ├── You own the types? → defimpl in each module
│   └── Third-party types? → defimpl in your protocol module
├── Dispatching on MODULE (callback contract)? → Behaviour
│   ├── Swappable implementations (prod/test)? → Behaviour + Mox
│   └── Plugin system? → Behaviour + Registry
└── Simple branching on values? → Pattern matching (function heads/case)
```

## Decision Tree: Control Flow

```
Which construct?
├── Multiple sequential operations that can fail? → with
├── Single value, multiple patterns? → case
├── Multiple boolean conditions? → cond
├── Two outcomes? → if/else (only for simple boolean)
├── Type/value dispatch? → Function heads with guards
└── Never: nested if/case — refactor to function heads or with
```

## Decision Tree: Error Handling

```
How to handle this error?
├── Business logic failure (expected)? → {:ok, val} / {:error, reason}
│   ├── Chain of operations? → with + pattern match on errors
│   └── Single operation? → case on result tuple
├── Programmer error (bug)? → raise / assert
├── External system failure? → {:error, reason} + let caller decide
├── Process crash (let it crash)? → Don't rescue, let supervisor restart
└── Must clean up resources? → try/after (rare)
```

## Pattern Matching Essentials

```elixir
# Function heads — preferred over case inside functions
def process(%User{role: :admin} = user), do: admin_path(user)
def process(%User{role: :member} = user), do: member_path(user)
def process(_), do: {:error, :invalid_user}

# Pin operator — match against existing binding
expected = "hello"
^expected = get_value()  # asserts equality

# Guards — extend pattern matching
def fetch(id) when is_binary(id), do: Repo.get(Thing, id)
def fetch(id) when is_integer(id), do: Repo.get(Thing, Integer.to_string(id))

# Custom guards
defguard is_positive(value) when is_number(value) and value > 0
```

## Data Transformation Idioms

```elixir
# Pipeline — always flows data left-to-right
data
|> Enum.filter(& &1.active)
|> Enum.map(&transform/1)
|> Enum.sort_by(& &1.name)

# Enum vs Stream
# Enum: eager, for bounded collections (99% of cases)
# Stream: lazy, for large/infinite sequences or multiple passes

# Access — nested data traversal
get_in(data, [:user, :address, :city])
update_in(data, [:user, :name], &String.upcase/1)
```

## Module Organization

```elixir
defmodule MyApp.Accounts.User do
  @moduledoc "User account with authentication and profile data."

  # 1. use/import/alias/require (in this order)
  use Ecto.Schema
  import Ecto.Changeset
  alias MyApp.Accounts.Organization

  # 2. Module attributes
  @primary_key {:id, :binary_id, autogenerate: true}

  # 3. Schema / struct / type definitions
  schema "users" do
    # ...
  end

  # 4. Public API functions
  # 5. Private functions (at bottom)
end
```

## Common Gotchas

- **Atoms are not garbage collected** — never convert user input to atoms
- **Large binaries** — sub-binaries reference parent; copy if parent is large
- **Timezone** — always store UTC, convert at boundaries (DateTime, not NaiveDateTime)
- **Decimal** — use `Decimal` for money, never Float
- **String vs charlist** — `"hello"` (binary) vs `'hello'` (charlist/Erlang), prefer binary

## References

- `references/idioms.md` — Pipeline patterns, comprehensions, recursive patterns
- `references/protocols-behaviours.md` — Full protocol/behaviour implementations
- `references/error-handling.md` — With chains, error structs, changeset errors
