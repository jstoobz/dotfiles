# Error Handling Reference

## Result Tuple Convention

The universal Elixir error pattern:

```elixir
{:ok, value}        # Success
{:error, reason}    # Failure (reason is atom, string, or struct)
```

## With Chains

### Basic Pattern

```elixir
def create_account(params) do
  with {:ok, user} <- validate_user(params),
       {:ok, org} <- create_organization(params),
       {:ok, membership} <- link_user_to_org(user, org) do
    {:ok, %{user: user, org: org, membership: membership}}
  end
  # Automatically returns first {:error, _} encountered
end
```

### Tagged Errors (for specific handling)

```elixir
def register(params) do
  with {:validate, {:ok, attrs}} <- {:validate, validate(params)},
       {:create, {:ok, user}} <- {:create, create_user(attrs)},
       {:notify, :ok} <- {:notify, send_welcome(user)} do
    {:ok, user}
  else
    {:validate, {:error, errors}} -> {:error, {:validation, errors}}
    {:create, {:error, changeset}} -> {:error, {:creation, changeset}}
    {:notify, {:error, reason}} ->
      # Non-critical — log and continue
      Logger.warning("Welcome email failed: #{reason}")
      {:ok, user}
  end
end
```

### Avoid: Deeply Nested With

```elixir
# BAD — too many steps, hard to follow
with {:ok, a} <- step1(),
     {:ok, b} <- step2(a),
     {:ok, c} <- step3(b),
     {:ok, d} <- step4(c),
     {:ok, e} <- step5(d),
     {:ok, f} <- step6(e) do
  {:ok, f}
end

# BETTER — extract into named function pipelines
def process(input) do
  with {:ok, prepared} <- prepare(input),
       {:ok, result} <- execute(prepared) do
    {:ok, result}
  end
end

defp prepare(input) do
  with {:ok, a} <- step1(input),
       {:ok, b} <- step2(a) do
    {:ok, b}
  end
end
```

## Error Structs

### Custom Error Module

```elixir
defmodule MyApp.DomainError do
  @type t :: %__MODULE__{
    code: atom(),
    message: String.t(),
    details: map()
  }
  defexception [:code, :message, :details]

  def not_found(resource, id) do
    %__MODULE__{
      code: :not_found,
      message: "#{resource} #{id} not found",
      details: %{resource: resource, id: id}
    }
  end

  def unauthorized(action) do
    %__MODULE__{
      code: :unauthorized,
      message: "Not authorized to #{action}",
      details: %{action: action}
    }
  end

  def validation_failed(errors) do
    %__MODULE__{
      code: :validation_failed,
      message: "Validation failed",
      details: %{errors: errors}
    }
  end
end
```

## Ecto Changeset Errors

### Extracting Error Messages

```elixir
# Traverse changeset errors to flat map
def format_errors(%Ecto.Changeset{} = changeset) do
  Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end)
end

# Usage
format_errors(changeset)
# => %{email: ["has already been taken"], name: ["can't be blank"]}
```

### Action-Based Error Display

```elixir
# Set action to trigger error display in forms
changeset = %User{} |> User.changeset(%{}) |> Map.put(:action, :validate)
```

## Rescue Patterns (Use Sparingly)

```elixir
# Only rescue at boundaries (HTTP, external APIs)
def fetch_external_data(url) do
  case HTTPoison.get(url) do
    {:ok, %{status_code: 200, body: body}} -> {:ok, Jason.decode!(body)}
    {:ok, %{status_code: status}} -> {:error, {:http_error, status}}
    {:error, %HTTPoison.Error{reason: reason}} -> {:error, {:connection_error, reason}}
  end
rescue
  Jason.DecodeError -> {:error, :invalid_json}
end

# Never rescue for flow control — use pattern matching
# Never rescue broad exceptions (RuntimeError, etc.)
```

## Process Error Handling

```elixir
# Let it crash — supervisor restarts
# DON'T:
def handle_info(:process, state) do
  try do
    result = dangerous_operation()
    {:noreply, %{state | result: result}}
  rescue
    e -> {:noreply, state}  # Silent failure!
  end
end

# DO:
def handle_info(:process, state) do
  result = dangerous_operation()  # Crashes → supervisor restarts
  {:noreply, %{state | result: result}}
end
```

## Pattern: Normalize External Errors

```elixir
# Wrap third-party errors at the boundary
defmodule MyApp.ExternalService do
  def call(params) do
    case ThirdParty.request(params) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:ok, %{"error" => msg}} -> {:error, {:service_error, msg}}
      {:error, :timeout} -> {:error, :service_timeout}
      {:error, reason} -> {:error, {:service_error, inspect(reason)}}
    end
  end
end
```
