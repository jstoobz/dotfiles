---
name: elixir-testing-expert
description: Elixir testing patterns — ExUnit organization, ExMachina factories, Mox boundary mocking, Bypass HTTP stubbing, parameterize, sandbox patterns, and async-safe concurrency
targets:
  elixir: "1.18+"
  ex_machina: "2.8+"
  mox: "1.2+"
  bypass: "2.1+"
  otp: "27+"
---

# Elixir Testing Expert

## When to Use This Skill

- Writing or organizing ExUnit tests, `setup` blocks, or test helpers
- Building factories with ExMachina (`build/insert/build_list/insert_list`)
- Mocking Elixir behaviours with Mox or stubbing HTTP with Bypass
- Configuring `async: true` safely with the Ecto SQL Sandbox and Mox allowances
- Testing GenServers, supervised processes, or async message flows
- Adopting `parameterize:` (1.18+) for table-driven tests
- **Skip this skill when designing schemas/queries (use `ecto-expert`), running production debugging (use `beam-expert`), or testing LiveView interactions specifically (use `liveview-expert` for `Phoenix.LiveViewTest`).**

## Mental Model

- **Mock the boundary, not the internals.** Mox is for swapping behaviour implementations at the *edge* of your system (mailer, payment gateway, external API). Mocking your own context modules is a smell — it means the test is coupled to your code's shape, not its behavior.
- **`async: true` is a feature AND a forcing function.** Async tests run in parallel — they catch shared-state bugs before production does. Code that breaks under async almost always relies on global state that will eventually bite you.
- **Assert on shape, not equality.** `assert {:ok, %User{email: "test@x"}} = result` is more resilient than `assert result == {:ok, %User{id: 1, email: "test@x", inserted_at: ..., ...}}`. Pattern matching ignores fields you don't care about.
- **Sandbox checkout is per-test ownership of a connection.** Async DB tests need `:manual` mode + per-test `Sandbox.checkout/1`. Without it, parallel tests step on each other's transactions. (See `ecto-expert` for sandbox config details.)

## Decision Tree: Test Organization

```
What are you testing?
├── Pure function (no DB, no I/O)? → async: true, no setup
├── Schema / changeset (no Repo)? → DataCase, async: true
├── Ecto query / context function? → DataCase, async: true (with manual sandbox)
├── HTTP controller? → ConnCase, async: true
├── LiveView? → load liveview-expert for Phoenix.LiveViewTest
├── External service call? → Mox + behaviour at the boundary, async: true
├── HTTP integration (real client, fake server)? → Bypass, async: true
├── GenServer behavior? → start_supervised!, assert_receive, async: true
├── Process communication / pubsub? → assert_receive, refute_receive
└── Multi-system integration / full stack? → DataCase, async: false (acceptance tests)
```

## Decision Tree: Mock vs Stub vs Real

```
What's the dependency you don't want to call for real?
├── External service with a behaviour you control? → Mox (verify expectations)
├── External HTTP service (any client lib)? → Bypass (real socket, fake server)
├── Internal context function? → DON'T mock — call it for real
│   └── Need to isolate failure? → Restructure to inject a behaviour at the seam
├── Time / DateTime.utc_now? → Inject a clock module behaviour, mock with Mox
├── Rand / unique IDs? → Inject and mock, OR seed deterministically
├── File system? → Use a temp dir (Briefly, ExUnit.Case `:tmp_dir`), real I/O
└── Database? → Real (sandboxed), never mock
```

## Decision Tree: Async Strategy

```
Should this test run async: true?
├── No DB, no shared state, no global config? → Yes, always
├── DB-touching, contexts use Repo? → Yes IF sandbox is :manual mode
├── Global config / Application.put_env? → No (or scope with on_exit)
├── Mox expectations? → Yes IF you use allow/3 for cross-process calls
├── Spawned processes / GenServer state? → Yes IF you start_supervised
├── Modifies a singleton GenServer (named process)? → No
└── Time-sensitive / sleep-based? → No (and probably refactor away the sleep)
```

## Core Patterns

### ExUnit essentials

```elixir
defmodule MyApp.AccountsTest do
  use MyApp.DataCase, async: true

  alias MyApp.Accounts
  alias MyApp.Accounts.User

  describe "create_user/1" do
    test "with valid data creates user" do
      attrs = %{email: "test@example.com", name: "Test User"}
      assert {:ok, %User{email: "test@example.com"}} = Accounts.create_user(attrs)
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(%{})
    end

    test "with duplicate email returns error" do
      insert(:user, email: "taken@example.com")
      assert {:error, changeset} = Accounts.create_user(%{email: "taken@example.com", name: "x"})
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_user/2" do
    setup do
      %{user: insert(:user)}
    end

    test "updates with valid attrs", %{user: user} do
      assert {:ok, updated} = Accounts.update_user(user, %{name: "New"})
      assert updated.name == "New"
    end
  end
end
```

**Rule:** Use `describe` per function under test. `setup` blocks scoped to a `describe` only run for tests in that block — use this to keep fixtures small.

### `start_link_supervised!` for supervised processes

```elixir
test "worker handles crash gracefully" do
  pid = start_link_supervised!({MyApp.Worker, []})

  GenServer.cast(pid, :crash_me)
  Process.sleep(50)

  assert Process.alive?(pid)  # restarted by ExUnit's supervisor
end
```

**Rule:** Prefer `start_link_supervised!` over `start_supervised!` when you want the test process to be linked to the started process — a supervisor crash will fail the test loudly instead of silently leaving zombies. Both auto-clean on test exit.

### ExMachina factories

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

  # Traits via composition
  def admin_factory do
    struct!(user_factory(), %{role: :admin})
  end

  # With associations
  def post_factory do
    %MyApp.Content.Post{
      title: sequence(:title, &"Post #{&1}"),
      body: "Content",
      author: build(:user)  # build = struct only, insert = DB write
    }
  end
end

# Usage
build(:user)                            # struct only, no DB
build(:user, role: :admin)              # with override
insert(:user)                           # inserted into DB
insert(:user, email: "specific@x.com")  # with override
build_list(3, :user)                    # list of 3
insert_list(5, :post)                   # 5 posts in DB
```

### Mox (mock behaviours)

```elixir
# 1. Define the behaviour
defmodule MyApp.Mailer do
  @callback send_email(String.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
end

# 2. Define the mock — typically in test/support/mocks.ex
Mox.defmock(MyApp.MockMailer, for: MyApp.Mailer)

# 3. Configure the app to use the mock in tests
# config/test.exs
config :my_app, :mailer, MyApp.MockMailer

# 4. Use in tests
defmodule MyApp.NotificationsTest do
  use MyApp.DataCase, async: true
  import Mox
  setup :verify_on_exit!  # fail test if expectations weren't met

  test "sends welcome email" do
    expect(MyApp.MockMailer, :send_email, fn to, subject, _body ->
      assert to == "user@example.com"
      assert subject =~ "Welcome"
      {:ok, :sent}
    end)

    assert {:ok, _} = Accounts.create_user_and_notify(%{email: "user@example.com"})
  end

  test "stub allows any number of calls" do
    stub(MyApp.MockMailer, :send_email, fn _, _, _ -> {:ok, :sent} end)
    # ... test code that may call send_email zero or many times
  end
end
```

### Mox in async tests (cross-process allowances)

```elixir
test "async-safe mock for spawned process" do
  test_pid = self()

  expect(MyApp.MockMailer, :send_email, fn _, _, _ ->
    send(test_pid, :email_sent)
    {:ok, :sent}
  end)

  # If create_user spawns a Task that calls the mock, the spawned process
  # needs explicit allowance — otherwise Mox raises "no expectations defined"
  Task.async(fn ->
    allow(MyApp.MockMailer, test_pid, self())
    Accounts.create_user(%{email: "x@y.com"})
  end)
  |> Task.await()

  assert_receive :email_sent
end
```

**Rule:** Mox expectations are owned by the process that calls `expect/3`. Other processes (spawned Tasks, GenServers) need explicit `allow/3` to use them, otherwise async tests fail mysteriously.

### Bypass (HTTP integration with a fake server)

```elixir
defmodule MyApp.WebhookClientTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    %{bypass: bypass, url: "http://localhost:#{bypass.port}"}
  end

  test "posts payload and parses response", %{bypass: bypass, url: url} do
    Bypass.expect(bypass, "POST", "/hooks", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"event" => "user.created"} = Jason.decode!(body)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"ok": true}))
    end)

    assert {:ok, %{"ok" => true}} = MyApp.WebhookClient.post(url <> "/hooks", %{event: "user.created"})
  end

  test "handles 5xx with retry intent", %{bypass: bypass, url: url} do
    Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 503, "") end)

    assert {:error, {:server_error, 503}} = MyApp.WebhookClient.post(url <> "/hooks", %{})
  end
end
```

**Rule:** Bypass tests the real HTTP client (HTTPoison, Req, Finch, etc.) against a real socket. Use it whenever you'd otherwise mock the HTTP client itself — Bypass catches request shape, headers, and body details that mocks can't.

### `parameterize:` for table-driven tests (1.18+)

```elixir
defmodule MyApp.Validators.EmailTest do
  use ExUnit.Case, async: true, parameterize: [
    %{input: "user@example.com", expected: :ok},
    %{input: "no-at-sign", expected: {:error, :invalid_format}},
    %{input: "trailing-dot@example.com.", expected: {:error, :invalid_format}},
    %{input: "", expected: {:error, :empty}},
    %{input: "  spaces  @example.com", expected: {:error, :invalid_format}}
  ]

  test "validates email", %{input: input, expected: expected} do
    assert MyApp.Validators.Email.validate(input) == expected
  end
end
```

**Rule:** `parameterize:` runs the same test once per parameter map, with the map merged into the test context. Cleaner than `Enum.each(cases, fn x -> test ... end)` and gives you per-case pass/fail in the test report.

### Async + Sandbox (DB tests)

```elixir
# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.DataCase
      import MyApp.Factory
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

**Rule:** `start_owner!` (modern API, replaced explicit `checkout`) handles per-test transaction ownership. Setting `shared: true` for non-async tests lets spawned processes share the connection; `shared: false` enforces per-process ownership. (See `ecto-expert` for full sandbox semantics.)

### Process communication testing

```elixir
test "GenServer sends notification" do
  {:ok, server} = start_link_supervised!({MyApp.Notifier, notify_pid: self()})
  MyApp.Notifier.trigger(server, :event)

  assert_receive {:notification, :event}, 1_000  # 1s timeout
  refute_receive {:notification, _}, 100         # 100ms timeout for absence
end
```

**Rule:** `assert_receive` timeout default is 100ms, which is too short for many real workflows. Always specify the timeout explicitly when the message could take longer than a tight loop.

## Anti-patterns

### Don't: mock things you own

```elixir
# BAD
defmock(MyApp.MockAccounts, for: MyApp.Accounts)  # you OWN MyApp.Accounts

test "controller delegates to context" do
  expect(MyApp.MockAccounts, :create_user, fn _ -> {:ok, %User{}} end)
  # ...
end
```

**Why it bites:** Mocking your own contexts means the test only verifies the controller calls the function — not that the system actually works. Refactoring the context (renaming, splitting) silently breaks production while tests still pass. The test is coupled to your code's *shape*, not its *behavior*.

**Instead:** Call your context functions for real. Mock only at the boundary — external services that have a behaviour and a swap point. If you find yourself wanting to mock an internal module, either restructure to inject a behaviour at the boundary, or use real fixtures.

### Don't: use `Process.sleep` to wait for async work

```elixir
# BAD
test "background job runs" do
  Accounts.create_user(%{email: "x@y.com"})
  Process.sleep(500)  # hope the worker finished
  assert Repo.get_by(EmailLog, type: "welcome")
end
```

**Why it bites:** Sleep is a guess. Too short → flaky test. Too long → slow suite. The actual time depends on machine load, CI noise, and what other tests are doing concurrently. Sleep-based tests fail on CI but pass locally.

**Instead:** Use `assert_receive` if the worker can signal completion, drain the Oban queue with `Oban.drain_queue/1` for synchronous execution in tests, or use `:inline` testing mode (see `oban-expert`). For LiveView, use `render_async` or `LiveViewTest.assert_patched/2` (see `liveview-expert`).

### Don't: assert on full struct equality

```elixir
# BAD
test "creates user" do
  expected = %User{
    id: 1, email: "x@y.com", name: "X", role: :member,
    inserted_at: ~U[2025-01-01 00:00:00Z], updated_at: ~U[2025-01-01 00:00:00Z],
    organization_id: nil, active: true, password_hash: nil
  }
  assert {:ok, ^expected} = Accounts.create_user(%{email: "x@y.com", name: "X"})
end
```

**Why it bites:** Adding any field to the schema breaks every test. The timestamps are nondeterministic. The `id` depends on whatever else ran in the suite. The test is fragile to changes that have nothing to do with the behavior under test.

**Instead:** Pattern-match on the fields that matter:

```elixir
# GOOD
assert {:ok, %User{email: "x@y.com", name: "X", role: :member}} =
  Accounts.create_user(%{email: "x@y.com", name: "X"})
```

Pattern matching ignores everything you don't list — adding fields doesn't break the test.

### Don't: leak global state into async tests

```elixir
# BAD
setup do
  Application.put_env(:my_app, :feature_x, true)  # GLOBAL — affects every concurrent test
  on_exit(fn -> Application.put_env(:my_app, :feature_x, false) end)
end
```

**Why it bites:** `Application.put_env/3` is process-global. Two async tests setting the same env var race; the second `on_exit` may run while the first test is still asserting. Tests pass individually, fail when async.

**Instead:** Inject configuration as a function parameter or via process dictionary scoped to the test, or set the test to `async: false` if there's no clean alternative. For feature flags specifically, pass them in to the function under test rather than reading from app env.

### Don't: write a test without `async: true` unless you have a reason

```elixir
# BAD (often)
defmodule MyApp.PureCalculationsTest do
  use ExUnit.Case   # no async
end
```

**Why it bites:** A 500-test suite with `async: false` runs serially. The same suite with `async: true` runs in parallel and finishes 5-10x faster. CI cost compounds. Worse, async tests catch shared-state bugs before they reach prod.

**Instead:** Default to `async: true`. Only drop async when there's a concrete reason (singleton GenServer, global config, real external HTTP). Document the reason inline.

## Common Gotchas

- **`assert_receive` default timeout is 100ms** — too short for real-world async work. Pass a timeout explicitly: `assert_receive msg, 1_000`. CI is often slower than local; budget accordingly.
- **`Mox.expect/3` is owned by the calling process** — spawned processes (Tasks, GenServers, Oban workers) need `Mox.allow/3` to use the expectation. Otherwise tests fail with "no expectations defined" in mysterious ways.
- **`setup_all` runs once per module, in its own process** — DB inserts in `setup_all` are visible to tests, but the process owning the connection is different from the test process. With async sandbox, this surprises everyone once.
- **`on_exit` callbacks run in LIFO order** — multiple `on_exit` registrations execute in reverse of registration order. Cleanup that depends on prior cleanup needs to register in dependency order.
- **`@moduletag :async` does not enable async** — to enable async at the module level, use `use ExUnit.Case, async: true`. Module tags are for filtering (`mix test --only :async`), not behavior.
- **`parameterize:` in 1.18+ is a `use` option, not a `@tag`** — `use ExUnit.Case, async: true, parameterize: [...]`. Each parameter map is merged into the test context.
- **`capture_log: true` captures Logger output** — useful for asserting on log content, but doesn't suppress log noise from the test runner unless you also configure Logger to be silent. Set `config :logger, level: :warning` in `config/test.exs` if log noise hides real issues.
- **`start_supervised!/1` vs `start_link_supervised!/1`** — both clean up at test exit, but only `start_link_supervised!` links the started process to the test process. Linking surfaces supervisor crashes immediately; unlinked failures may be invisible.
- **`async: true` and `Mox.set_mox_global/0` are mutually exclusive** — `set_mox_global` makes a mock available to every process but precludes async (it's literally a global override). Use `set_mox_from_context/1` + `verify_on_exit!` for async-safe Mox setup.
- **`describe` block names are part of the test name** — renaming `describe "create_user/1"` to `describe "create user"` changes test identity and breaks `mix test path/to/file.exs:LINE` workflows that assume names. Rename deliberately.

## Quick Reference

```
ExUnit setup options (use ExUnit.Case, ...):
  async: true                          # run module's tests concurrently
  parameterize: [%{...}, %{...}]       # 1.18+: run each test per param map

Test lifecycle:
  setup_all          # once per module, separate process
  setup              # per test, in test process
  on_exit            # per test, runs in LIFO order at test end

Process helpers:
  start_supervised!({Mod, args})       # ExUnit owns; auto-cleanup
  start_link_supervised!({Mod, args})  # ExUnit owns AND links to test process

Async assertions:
  assert_receive pattern, timeout      # default 100ms (often too short)
  refute_receive pattern, timeout      # default 100ms
  assert_received pattern              # already in mailbox, no wait

Pattern-match assertions:
  assert {:ok, %User{email: ^e}} = result
  assert %{name: "X", role: :admin} = user   # ignores other fields

Mox essentials:
  Mox.defmock(MyMock, for: MyBehaviour)      # in test/support
  expect(MyMock, :fun, fn ... -> ... end)    # one call expected
  expect(MyMock, :fun, n, fn ... end)        # n calls expected
  stub(MyMock, :fun, fn ... -> ... end)      # any number of calls
  allow(MyMock, owner_pid, allowed_pid)      # cross-process
  verify_on_exit!()                          # in setup, fails if expectations unmet

Bypass essentials:
  bypass = Bypass.open()
  Bypass.expect(bypass, "POST", "/path", fn conn -> ... end)
  Bypass.expect_once(bypass, fn conn -> ... end)
  Bypass.down(bypass)                        # simulate server outage
```

## When to Load Deeper References

- Setting up complex Mox scenarios (multi-mock chains, global allowances, capturing call sequences)? → Read `references/mox-patterns.md`
- Writing property-based tests with StreamData (custom generators, shrinking, domain modeling)? → Read `references/property-based.md`
