---
name: elixir-expert
description: Core Elixir language patterns — pipelines, pattern matching, with-chains, protocols, error handling, set-theoretic types, JSON, and modern idioms
targets:
  elixir: "1.18+"
  otp: "27+"
---

# Elixir Expert

## When to Use This Skill

- Writing or reviewing Elixir code at the language level: pipelines, pattern matching, `with` chains, comprehensions, recursion
- Designing custom protocols or behaviours
- Choosing data structures (struct vs map vs keyword vs MapSet) or control-flow constructs
- Adopting modern features: set-theoretic types (`@spec`), `Mix.install/2`, the built-in `JSON` module, `Duration`
- Refactoring nested `case`/`if` chains into idiomatic Elixir
- **Skip this skill when working in a specific framework (use `phoenix-expert`, `ecto-expert`, `liveview-expert`, `commanded-expert`, etc.) or when designing process structure / supervision / debugging the BEAM (use `beam-expert`).**

## Core Philosophy

- **Immutability by default** — data flows through pipelines; nothing mutates in place.
- **Let it crash** — design for recovery via supervision (see `beam-expert`), not defensive `try/rescue` everywhere.
- **Explicit over implicit** — no magic, no hidden state, no surprising side effects.
- **Composition over inheritance** — behaviours and protocols, not class hierarchies.
- **Small, pure functions composed via pipes** — readability is a feature, not a luxury.

## Decision Tree: Data Structures

```
Need key-value data?
├── Fixed keys known at compile time, want shape enforcement? → Struct
│   └── Type-safe field access? → Use defstruct + @type t
├── Dynamic/unknown keys, runtime-shaped? → Map
├── Ordered options or small config (passed to functions)? → Keyword list
├── Need default values when key absent? → Keyword.get/3 or Map.get/3
├── Set membership / uniqueness? → MapSet
├── Sorted traversal / range queries? → :gb_trees or :ordsets
└── Passing to Ecto/Phoenix/external API? → Match what the API expects
```

## Decision Tree: Polymorphism

```
Need different behavior per data type?
├── Dispatching on data TYPE (struct or built-in)? → Protocol
│   ├── You own the types? → defimpl in each module
│   └── Third-party types? → defimpl Protocol, for: ThirdParty.Struct
├── Dispatching on MODULE (callback contract)? → Behaviour
│   ├── Swappable implementations (prod vs test)? → Behaviour + Mox
│   └── Plugin / extension system? → Behaviour + Registry
└── Simple branching on values? → Pattern matching (function heads or case)
```

## Decision Tree: Control Flow

```
Which construct?
├── Multiple sequential operations that can fail? → with
├── Single value, multiple patterns to match? → case
├── Multiple boolean conditions to evaluate? → cond
├── Two simple outcomes? → if/else (boolean only — never nest)
├── Type or value dispatch in a function? → Function heads with guards
└── Avoid: nested if/case — refactor to function heads or with
```

## Decision Tree: Error Handling

```
How to handle this failure?
├── Business logic failure (expected, recoverable)? → {:ok, val} / {:error, reason}
│   ├── Chain of operations? → with + pattern match the error
│   └── Single operation? → case on the result tuple
├── Programmer error (bug, invariant violated)? → raise (or assert in tests)
├── External system failure? → {:error, reason} — let the caller decide
├── Process crash (let it crash)? → don't rescue; let the supervisor restart
└── Must clean up resources? → try/after (rare; prefer Erlang-style ownership)
```

## Core Patterns

### Pattern matching essentials

```elixir
# Function heads — preferred over `case` inside functions
def process(%User{role: :admin} = user), do: admin_path(user)
def process(%User{role: :member} = user), do: member_path(user)
def process(_), do: {:error, :invalid_user}

# Pin operator — match against an existing binding
expected = "hello"
^expected = get_value()  # asserts equality

# Guards extend pattern matching
def fetch(id) when is_binary(id), do: Repo.get(Thing, id)
def fetch(id) when is_integer(id), do: Repo.get(Thing, Integer.to_string(id))

# Custom guards
defguard is_positive(value) when is_number(value) and value > 0
```

**Rule:** Pattern match in function heads first; reach for `case` only when you must inspect a value computed inside the function body.

### `with` for chained validations

```elixir
def create_user(attrs) do
  with {:ok, validated} <- validate(attrs),
       {:ok, user} <- Repo.insert(User.changeset(%User{}, validated)),
       {:ok, _} <- Notifier.welcome(user) do
    {:ok, user}
  end
end
# Any {:error, _} short-circuits and is returned as-is.
```

**Rule:** Use `with` whenever you have 2+ sequential operations that each return a result tuple. Adding `else` clauses transforms specific errors into other shapes; usually you don't need it.

### Data transformation pipelines

```elixir
# Pipelines flow data left-to-right, one step per line
data
|> Enum.filter(& &1.active)
|> Enum.map(&transform/1)
|> Enum.sort_by(& &1.name)

# Enum vs Stream:
# - Enum: eager — for bounded collections (99% of cases)
# - Stream: lazy — for large/infinite sequences or multiple passes

# Access — nested data traversal
get_in(data, [:user, :address, :city])
update_in(data, [:user, :name], &String.upcase/1)
```

### Set-theoretic types (Elixir 1.17+)

```elixir
defmodule Post do
  @type status :: :draft or :published or :archived
  @type t :: %__MODULE__{
    id: integer(),
    title: String.t(),
    status: status(),
    body: String.t() or nil
  }

  defstruct [:id, :title, :status, :body]

  @spec status_label(t()) :: String.t()
  def status_label(%__MODULE__{status: :draft}), do: "Draft"
  def status_label(%__MODULE__{status: :published}), do: "Live"
  def status_label(%__MODULE__{status: :archived}), do: "Archived"
end
```

**Rule:** Set-theoretic types (`or`, `and`, `not`) replace nested unions in `@type` and `@spec`. Use them — the new compiler can catch type mismatches statically that classical typespecs couldn't.

### JSON encoding (built-in since 1.18)

```elixir
# Encode
JSON.encode!(%{name: "Ada", age: 36})
# => "{\"name\":\"Ada\",\"age\":36}"

# Decode (returns {:ok, term} | {:error, reason})
{:ok, data} = JSON.decode(~s({"name":"Ada"}))

# In OTP 27+, you can also use the Erlang :json module
:json.encode(%{ok: true})
```

**Rule:** Reach for the built-in `JSON` module for new code. Existing apps using `Jason` keep working — switching is optional, not urgent. Stick with one library per project.

### `Mix.install/2` for one-shot scripts

```elixir
#!/usr/bin/env elixir
Mix.install([
  {:req, "~> 0.5"},
  {:jason, "~> 1.4"}
])

%{body: body} = Req.get!("https://api.example.com/users")
IO.inspect(body)
```

**Rule:** `Mix.install/2` lets a single `.exs` file declare deps without a project. Perfect for ad-hoc scripts, one-off automation, gist examples — anything where spinning up a `mix new` is overkill.

### Module organization

```elixir
defmodule MyApp.Accounts.User do
  @moduledoc "User account with authentication and profile data."

  # 1. use / import / alias / require — in this order
  use Ecto.Schema
  import Ecto.Changeset
  alias MyApp.Accounts.Organization

  # 2. Module attributes
  @primary_key {:id, :binary_id, autogenerate: true}

  # 3. Type definitions
  @type t :: %__MODULE__{...}

  # 4. Schema / struct definitions
  schema "users" do
    # ...
  end

  # 5. Public API functions

  # 6. Private functions (at the bottom)
end
```

## Anti-patterns

### Don't: convert user input to atoms

```elixir
# BAD
def parse_event(%{"type" => type} = params) do
  String.to_atom(type)  # attacker-controlled atoms
end
```

**Why it bites:** Atoms are not garbage-collected. There's a global atom table with a hard limit (default ~1M). An attacker who can post arbitrary `type` values exhausts the atom table; the BEAM crashes. Even without an attacker, organic growth from user input eventually hits the wall.

**Instead:**

```elixir
# GOOD
@allowed_types ~w(login logout signup)
def parse_event(%{"type" => type}) when type in @allowed_types do
  String.to_existing_atom(type)
end
```

`String.to_existing_atom/1` raises if the atom doesn't already exist — bounded by the atoms your code already uses.

### Don't: nest `case`/`if` instead of using `with` or function heads

```elixir
# BAD
def show(conn, %{"id" => id}) do
  case Accounts.fetch_user(id) do
    {:ok, user} ->
      case Authorization.can_view?(conn.assigns.current_user, user) do
        :ok ->
          case Repo.preload(user, :posts) do
            user_with_posts -> render(conn, :show, user: user_with_posts)
          end
        {:error, reason} -> render_error(conn, reason)
      end
    {:error, :not_found} -> render_404(conn)
  end
end
```

**Why it bites:** The arrow-shaped indentation hides the failure paths; reviewers can't see what each `{:error, _}` does without tracing the whole function. Adding a step means restructuring the whole pyramid.

**Instead:**

```elixir
# GOOD
def show(conn, %{"id" => id}) do
  with {:ok, user} <- Accounts.fetch_user(id),
       :ok <- Authorization.can_view?(conn.assigns.current_user, user),
       user_with_posts <- Repo.preload(user, :posts) do
    render(conn, :show, user: user_with_posts)
  end
end
```

Errors flow out of `with` as `{:error, _}` and are handled by `action_fallback` (in Phoenix controllers) or matched in an `else` clause.

### Don't: use exceptions for control flow

```elixir
# BAD
def get_user(id) do
  try do
    Accounts.get_user!(id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
```

**Why it bites:** Exceptions are slow to raise (BEAM has to construct a stack trace), bypass the type system, and turn what should be an explicit failure path into invisible control flow. The bang variant exists *for* the case where missing data is a bug; using it then catching means you should be using the non-bang variant.

**Instead:**

```elixir
# GOOD
def get_user(id), do: Repo.get(User, id)  # returns nil if not found
```

Use `!` variants when missing data should crash; use non-bang variants when missing data is a normal outcome.

### Don't: use the process dictionary for state

```elixir
# BAD
def process(items) do
  Process.put(:total, 0)
  Enum.each(items, fn item ->
    Process.put(:total, Process.get(:total) + item.amount)
  end)
  Process.get(:total)
end
```

**Why it bites:** Process dictionary is invisible in the function signature, untestable, and refactor-hostile. Code that reads via `Process.get/1` silently changes behavior depending on which process happens to execute it.

**Instead:** Use `Enum.reduce/3` or accumulate explicitly. The few legitimate process-dictionary uses (Logger metadata) are infrastructure, not application state.

### Don't: turn `Enum` chains into `Stream` chains "for performance"

```elixir
# BAD (premature optimization, harder to read)
data
|> Stream.filter(&active?/1)
|> Stream.map(&transform/1)
|> Enum.to_list()
```

**Why it bites:** Stream pipelines are lazy — they're a win when (a) you have very large data, (b) you'd otherwise allocate large intermediate lists, or (c) you want to short-circuit. For bounded data with a few thousand items, `Enum` is faster (less overhead) and clearer.

**Instead:** Default to `Enum`. Reach for `Stream` when you have a measured reason: huge inputs, multiple passes you can fuse, or you need lazy evaluation.

## Common Gotchas

- **`erlang:phash2` over maps with >32 keys is unstable** — Maps switch internal representation from sorted `flat_map` to HAMT once they exceed 32 keys. `phash2` hashes the term representation, so two logically-equal maps can produce different hashes if one has ≤32 keys and the other has >32. If you need stable structural hashes, hash a sorted list of `Map.to_list/1` output instead. (See `beam-expert` for the term-representation deep dive.)
- **Atoms are NOT garbage collected** — never convert untrusted input to atoms. Use `String.to_existing_atom/1` when you must convert at all.
- **Large binaries — sub-binaries reference the parent** — slicing a 100MB binary into a 10-byte slice keeps the whole 100MB alive. Use `:binary.copy/1` to detach the slice.
- **`DateTime` vs `NaiveDateTime`** — always store UTC, convert at the boundary. `NaiveDateTime` has no zone and silently drifts. Phoenix and Ecto default to `DateTime` for good reason.
- **`Decimal` for money, never Float** — IEEE-754 binary floats can't represent `0.1` exactly. Use `Decimal` for any value where precision matters.
- **String vs charlist** — `"hello"` is a UTF-8 binary; `~c"hello"` is a charlist (Erlang convention). Erlang libraries usually want charlists; Elixir prefers binaries. The compiler now warns on charlist string literals so they don't sneak in.
- **`Map.update!/3` raises on missing key, `Map.update/4` doesn't** — easy to miss. The bang version is for "key MUST exist or it's a bug"; the non-bang version takes a default.
- **`%{}` pattern matches ANY map** — `case x do %{} -> :map; _ -> :other end` matches any map including ones with no keys. To require an empty map, check `map_size(x) == 0`.
- **`Duration` (1.17+) is not interchangeable with integer seconds** — adding a `Duration` to a `DateTime` works; passing a `Duration` where seconds are expected does not.
- **Set-theoretic type warnings show up at compile time only** — they don't run during normal app boot. CI must run `mix compile --warnings-as-errors` to enforce them.

## Quick Reference

```
String basics:
  String.split("a,b,c", ",")           # ["a", "b", "c"]
  String.trim/1, String.upcase/1, String.length/1 (graphemes)
  String.contains?("hello", "ell")
  String.replace("a-b-c", "-", "_")

Enum essentials:
  Enum.map/2, Enum.filter/2, Enum.reduce/3
  Enum.zip/2, Enum.unzip/1, Enum.chunk_every/2
  Enum.group_by/2, Enum.frequencies/1
  Enum.sort_by(list, & &1.name)
  Enum.find/2, Enum.find_index/2
  Enum.any?/2, Enum.all?/2, Enum.empty?/1

Map operations:
  Map.get/3 (with default), Map.fetch/2 ({:ok, _} | :error), Map.fetch!/2 (raises)
  Map.put/3, Map.delete/2, Map.merge/2, Map.merge/3 (with conflict fn)
  Map.update/4, Map.update!/3 (raises on missing key)
  Map.new(list_of_tuples), Map.to_list/1
  for {k, v} <- map, into: %{}, do: {k, transform(v)}

Common type specs (with set-theoretic syntax):
  @type id :: integer()
  @type maybe(t) :: t or nil
  @type result(ok) :: {:ok, ok} or {:error, term()}
  @spec parse(String.t()) :: result(integer())
```

## When to Load Deeper References

- Refining a complex pipeline, comprehension form, or recursive function pattern? → Read `references/idioms.md`
- Defining a custom protocol or behaviour with multiple implementations and dispatch rules? → Read `references/protocols-behaviours.md`
- Designing error flow with `with` chains, custom error structs, or changeset-style error accumulation? → Read `references/error-handling.md`
