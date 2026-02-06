# Mox Patterns Reference

## Setup

```elixir
# test/support/mocks.ex — define all mocks
Mox.defmock(MyApp.MockMailer, for: MyApp.Mailer)
Mox.defmock(MyApp.MockPaymentProvider, for: MyApp.PaymentProvider)
Mox.defmock(MyApp.MockExternalAPI, for: MyApp.ExternalAPI)

# config/test.exs — wire up
config :my_app, :mailer, MyApp.MockMailer
config :my_app, :payment_provider, MyApp.MockPaymentProvider

# Application code — use config
defmodule MyApp.Notifications do
  defp mailer, do: Application.get_env(:my_app, :mailer, MyApp.RealMailer)

  def send_welcome(user) do
    mailer().send_email(user.email, "Welcome!", welcome_body(user))
  end
end
```

## Expect vs Stub

```elixir
import Mox

# expect — must be called exactly N times (default 1)
expect(MockMailer, :send_email, fn to, _subject, _body ->
  assert to == "user@example.com"
  {:ok, :sent}
end)

# expect N times
expect(MockMailer, :send_email, 3, fn _to, _subject, _body -> {:ok, :sent} end)

# stub — any number of calls (0 or more)
stub(MockMailer, :send_email, fn _to, _subject, _body -> {:ok, :sent} end)

# IMPORTANT: Always call verify! at end of test (or use verify_on_exit!)
verify!()

# Better: Use setup to auto-verify
setup :verify_on_exit!
```

## Multi-Mock Scenarios

```elixir
test "processes payment and sends receipt" do
  # Set up multiple mocks for a workflow
  expect(MockPaymentProvider, :charge, fn amount, _card ->
    assert Decimal.equal?(amount, Decimal.new("99.99"))
    {:ok, %{transaction_id: "txn_123"}}
  end)

  expect(MockMailer, :send_email, fn to, subject, _body ->
    assert to == "customer@example.com"
    assert subject =~ "Receipt"
    {:ok, :sent}
  end)

  assert {:ok, _order} = Orders.complete_purchase(order, card_info)
end
```

## Ordered Expectations

```elixir
test "retries payment then sends failure notice" do
  # First call fails
  expect(MockPaymentProvider, :charge, fn _, _ -> {:error, :declined} end)
  # Second call also fails
  expect(MockPaymentProvider, :charge, fn _, _ -> {:error, :declined} end)
  # Then failure email sent
  expect(MockMailer, :send_email, fn _, subject, _ ->
    assert subject =~ "Payment Failed"
    {:ok, :sent}
  end)

  assert {:error, :payment_failed} = Orders.complete_purchase(order, card_info)
end
```

## Async-Safe Mocking

```elixir
# In async tests, allowances are needed for processes you don't own
test "background worker uses mock", %{} do
  parent = self()

  # Allow the Oban worker process to use this test's mock
  allow(MockExternalAPI, parent, fn -> :ok end)
  # OR: set Mox to global mode (careful — not truly async-safe)

  expect(MockExternalAPI, :fetch, fn id ->
    assert id == "123"
    {:ok, %{data: "result"}}
  end)

  # Perform the Oban job which will call MockExternalAPI
  assert :ok = perform_job(Workers.SyncExternal, %{id: "123"})
end

# Global mode (simpler but limits parallelism)
setup do
  Mox.set_mox_global()
  :ok
end
```

## Dynamic Return Values

```elixir
test "handles varying responses" do
  responses = [:ok, {:error, :timeout}, :ok]
  agent = start_supervised!({Agent, fn -> responses end})

  stub(MockExternalAPI, :call, fn _args ->
    Agent.get_and_update(agent, fn
      [response | rest] -> {response, rest}
      [] -> {:ok, []}
    end)
  end)

  # First call succeeds, second fails, third succeeds
  assert :ok = Service.call_external("a")
  assert {:error, :timeout} = Service.call_external("b")
  assert :ok = Service.call_external("c")
end
```

## Testing Module That Uses Multiple Behaviours

```elixir
defmodule MyApp.OrderProcessor do
  @payment Application.compile_env(:my_app, :payment_provider)
  @mailer Application.compile_env(:my_app, :mailer)
  @inventory Application.compile_env(:my_app, :inventory)

  def process(order) do
    with {:ok, payment} <- @payment.charge(order.total, order.card),
         {:ok, _} <- @inventory.reserve(order.items),
         {:ok, _} <- @mailer.send_email(order.email, "Confirmed", body(order)) do
      {:ok, %{order | status: :confirmed, payment_id: payment.id}}
    end
  end
end

test "full happy path" do
  expect(MockPaymentProvider, :charge, fn _, _ -> {:ok, %{id: "pay_1"}} end)
  expect(MockInventory, :reserve, fn items -> {:ok, items} end)
  expect(MockMailer, :send_email, fn _, _, _ -> {:ok, :sent} end)

  assert {:ok, %{status: :confirmed}} = OrderProcessor.process(order)
end

test "rolls back on inventory failure" do
  expect(MockPaymentProvider, :charge, fn _, _ -> {:ok, %{id: "pay_1"}} end)
  expect(MockInventory, :reserve, fn _ -> {:error, :out_of_stock} end)
  # Mailer should NOT be called
  # verify! will catch unexpected calls

  assert {:error, :out_of_stock} = OrderProcessor.process(order)
end
```
