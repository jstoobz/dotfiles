# Protocols and Behaviours Reference

## When to Use Which

| Feature        | Protocol                    | Behaviour                    |
| -------------- | --------------------------- | ---------------------------- |
| Dispatch on    | Data type (struct)          | Module (implementation)      |
| Defined by     | `defprotocol`               | `@callback` in module        |
| Implemented by | `defimpl` per type          | `@behaviour` + function defs |
| Use case       | Polymorphic data            | Swappable implementations    |
| Example        | Jason.Encoder, String.Chars | GenServer, Plug              |

## Protocol Implementation

### Define Protocol

```elixir
defprotocol Renderable do
  @doc "Render the item to a display string"
  @fallback_to_any true
  def render(item)
end
```

### Implement for Specific Types

```elixir
defimpl Renderable, for: MyApp.User do
  def render(%{name: name, role: role}) do
    "#{name} (#{role})"
  end
end

defimpl Renderable, for: MyApp.Organization do
  def render(%{name: name, member_count: count}) do
    "#{name} — #{count} members"
  end
end

# Fallback for all other types
defimpl Renderable, for: Any do
  def render(item), do: inspect(item)
end
```

### Derive Protocol (for simple cases)

```elixir
# In the protocol definition, enable deriving:
defprotocol Displayable do
  @fallback_to_any true
  def display(item)
end

# In the struct:
defmodule MyApp.User do
  @derive {Displayable, key: :name}
  defstruct [:name, :email]
end
```

### Built-in Protocol Implementations

```elixir
# Jason.Encoder — control JSON serialization
defimpl Jason.Encoder, for: Money do
  def encode(%{amount: amount, currency: currency}, opts) do
    Jason.Encode.map(%{amount: amount, currency: currency}, opts)
  end
end

# String.Chars — control "#{thing}" interpolation
defimpl String.Chars, for: Money do
  def to_string(%{amount: amount, currency: currency}) do
    "$#{Decimal.to_string(amount)} #{currency}"
  end
end

# Inspect — control inspect() output
defimpl Inspect, for: SecretToken do
  def inspect(_token, _opts), do: "#SecretToken<redacted>"
end
```

## Behaviour Implementation

### Define Behaviour

```elixir
defmodule MyApp.PaymentProvider do
  @doc "Process a payment for the given amount"
  @callback process_payment(amount :: Decimal.t(), currency :: String.t()) ::
              {:ok, transaction_id :: String.t()} | {:error, reason :: String.t()}

  @callback refund(transaction_id :: String.t()) ::
              {:ok, refund_id :: String.t()} | {:error, reason :: String.t()}

  @doc "Optional callback with default implementation"
  @callback supports_currency?(currency :: String.t()) :: boolean()
  @optional_callbacks supports_currency?: 1
end
```

### Implement Behaviour

```elixir
defmodule MyApp.StripeProvider do
  @behaviour MyApp.PaymentProvider

  @impl true
  def process_payment(amount, currency) do
    # Stripe-specific implementation
    {:ok, "txn_#{System.unique_integer([:positive])}"}
  end

  @impl true
  def refund(transaction_id) do
    {:ok, "rfnd_#{transaction_id}"}
  end

  # Optional callback not implemented — uses default if defined
end
```

### Runtime Module Selection

```elixir
# Config-driven selection
defmodule MyApp.Payments do
  def provider do
    Application.get_env(:my_app, :payment_provider, MyApp.StripeProvider)
  end

  def process(amount, currency) do
    provider().process_payment(amount, currency)
  end
end

# In config:
config :my_app, :payment_provider, MyApp.StripeProvider

# In test config:
config :my_app, :payment_provider, MyApp.MockPaymentProvider
```

### Behaviour + Mox (Testing)

```elixir
# Define mock in test/support/mocks.ex
Mox.defmock(PaymentProviderMock, for: MyApp.PaymentProvider)

# Configure in test
config :my_app, :payment_provider, PaymentProviderMock

# Use in test
test "processes payment" do
  expect(PaymentProviderMock, :process_payment, fn amount, _currency ->
    assert Decimal.equal?(amount, Decimal.new("100.00"))
    {:ok, "txn_123"}
  end)

  assert {:ok, "txn_123"} = MyApp.Payments.process(Decimal.new("100.00"), "USD")
end
```

## Module Attribute Patterns

```elixir
defmodule MyApp.Config do
  # Compile-time constant
  @default_timeout 5_000

  # Accumulate attribute (list)
  Module.register_attribute(__MODULE__, :events, accumulate: true)
  @events :user_created
  @events :user_updated

  # Access accumulated
  def events, do: @events  # [:user_updated, :user_created]
end
```
