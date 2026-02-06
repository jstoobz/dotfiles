---
name: elixir-testing-expert
description: Elixir testing patterns including ExUnit, ExMachina factories, Mox mocks, property-based testing, and async patterns
---

# Elixir Testing Expert

## Decision Tree: Test Organization

```
What are you testing?
├── Pure function (no DB, no side effects)? → async: true, no setup
├── Schema / changeset? → DataCase, async: true
├── Ecto query / context function? → DataCase, async: true
├── Command handler (CQRS)? → DataCase, may need async: false
├── Aggregate logic? → AggregateCase (no DB needed)
├── GraphQL endpoint? → AbsintheCase or ConnCase
├── HTTP controller? → ConnCase, async: true
├── LiveView? → LiveView test, ConnCase
├── External service call? → Mox, async: true
├── GenServer behavior? → start in test, assert_receive
├── Process communication? → assert_receive, refute_receive
└── Integration / full stack? → DataCase, async: false
```

## ExUnit Patterns

```elixir
defmodule MyApp.AccountsTest do
  use MyApp.DataCase, async: true

  alias MyApp.Accounts
  alias MyApp.Accounts.User

  describe "create_user/1" do
    test "with valid data creates user" do
      attrs = %{email: "test@example.com", name: "Test User"}
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == "test@example.com"
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(%{})
    end

    test "with duplicate email returns error" do
      insert(:user, email: "taken@example.com")
      assert {:error, changeset} = Accounts.create_user(%{email: "taken@example.com", name: "New"})
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  # Setup with shared context
  describe "update_user/2" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "updates with valid attrs", %{user: user} do
      assert {:ok, updated} = Accounts.update_user(user, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end
end
```

## ExMachina Factories

```elixir
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def user_factory do
    %MyApp.Accounts.User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: sequence(:name, &"User #{&1}"),
      role: :member,
      active: true
    }
  end

  # Traits via function composition
  def admin_factory do
    struct!(user_factory(), role: :admin)
  end

  # With associations
  def post_factory do
    %MyApp.Content.Post{
      title: sequence(:title, &"Post #{&1}"),
      body: "Content",
      author: build(:user)  # build (no DB) vs insert (DB)
    }
  end
end

# Usage:
build(:user)                          # struct only, no DB
build(:user, role: :admin)            # with override
insert(:user)                         # inserted into DB
insert(:user, email: "specific@x.com") # with override
build_list(3, :user)                  # list of 3
insert_list(5, :post)                 # 5 posts in DB
```

## Mox (Mock Behaviour)

```elixir
# 1. Define behaviour
defmodule MyApp.Mailer do
  @callback send_email(String.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
end

# 2. Define mock in test/support/mocks.ex
Mox.defmock(MyApp.MockMailer, for: MyApp.Mailer)

# 3. Configure in test
config :my_app, :mailer, MyApp.MockMailer

# 4. Use in test
import Mox

test "sends welcome email" do
  expect(MyApp.MockMailer, :send_email, fn to, subject, _body ->
    assert to == "user@example.com"
    assert subject =~ "Welcome"
    {:ok, :sent}
  end)

  assert {:ok, _} = Accounts.create_user_and_notify(%{email: "user@example.com"})
  verify!()  # Ensure all expectations were called
end

# Stub (allow any number of calls)
stub(MyApp.MockMailer, :send_email, fn _, _, _ -> {:ok, :sent} end)

# Allow in async tests (explicit process allowance)
test "async-safe mock", %{test: test_name} do
  parent = self()
  allow(MyApp.MockMailer, parent, self())  # Allow current process

  expect(MyApp.MockMailer, :send_email, fn _, _, _ -> {:ok, :sent} end)
  # ...
end
```

## Async and Concurrency

```elixir
# Sandbox mode for async DB tests
# In test/support/data_case.ex:
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, {:shared, self()})
  end
  :ok
end

# Process communication testing
test "GenServer sends notification" do
  {:ok, server} = MyApp.Notifier.start_link(notify_pid: self())
  MyApp.Notifier.trigger(server, :event)

  assert_receive {:notification, :event}, 1_000  # 1s timeout
  refute_receive {:notification, _}, 100          # 100ms timeout
end

# Testing supervised processes
test "worker handles crash gracefully" do
  start_supervised!({MyApp.Worker, []})
  # Worker is started and linked to test process supervisor
  # Will be cleaned up after test
end
```

## Assertion Patterns

```elixir
# Pattern matching assertions
assert {:ok, %User{email: "test@example.com"}} = Accounts.create_user(attrs)
assert {:error, %Ecto.Changeset{valid?: false}} = Accounts.create_user(%{})

# Changeset error helpers
assert %{email: ["can't be blank"]} = errors_on(changeset)

# List assertions
assert length(users) == 3
assert Enum.any?(users, &(&1.email == "specific@example.com"))

# Map subset
assert %{name: "Test", role: :admin} = user  # ignores other keys

# Raise assertion
assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(bad_id) end

# Approximately equal (for floats/times)
assert_in_delta 3.14, result, 0.01
```

## Test Tags and Selection

```elixir
# Tag individual tests
@tag :slow
test "expensive operation" do ... end

@tag :integration
test "calls external API" do ... end

# Tag entire module
@moduletag :integration

# Run tagged tests
# mix test --only slow
# mix test --only integration
# mix test --exclude slow
```

## References

- `references/mox-patterns.md` — Complex Mox scenarios, multi-mock setups, async-safe patterns
- `references/property-based.md` — StreamData generators, domain type generators, shrinking
