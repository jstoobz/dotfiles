# Oban Testing Recipes Reference

## Setup Modes

```elixir
# config/test.exs

# Option 1: :inline — jobs execute synchronously during insert
config :my_app, Oban, testing: :inline
# Pros: Simple, no drain needed
# Cons: Side effects happen during insert, can't test enqueue-only

# Option 2: :manual — jobs are enqueued but not executed
config :my_app, Oban, testing: :manual
# Pros: Full control, can test enqueue separately from execution
# Cons: Must drain_queue or perform_job explicitly
```

## Assert/Refute Enqueued

```elixir
use Oban.Testing, repo: MyApp.Repo

test "enqueues notification job" do
  Accounts.create_user(%{email: "new@example.com"})

  # Basic assertion
  assert_enqueued worker: Workers.SendEmail

  # With specific args
  assert_enqueued worker: Workers.SendEmail,
    args: %{template: "welcome"}

  # With queue
  assert_enqueued worker: Workers.SendEmail,
    queue: :notifications

  # With schedule
  assert_enqueued worker: Workers.DailyReport,
    scheduled_at: ~U[2024-01-01 02:00:00Z]

  # Refute
  refute_enqueued worker: Workers.SendEmail,
    args: %{template: "goodbye"}
end
```

## Perform Job Directly

```elixir
test "processes import correctly" do
  import_data = insert(:import, status: :pending)

  # Execute the worker's perform function directly
  assert :ok = perform_job(Workers.ProcessImport, %{import_id: import_data.id})

  # Verify side effects
  updated = Repo.get!(Import, import_data.id)
  assert updated.status == :completed
end

test "handles errors gracefully" do
  assert {:error, _reason} = perform_job(Workers.ProcessImport, %{import_id: "nonexistent"})
end

test "discards permanently failed jobs" do
  assert {:discard, _reason} = perform_job(Workers.ValidateData, %{data: "invalid"})
end
```

## Drain Queue

```elixir
test "processes all pending emails" do
  # Enqueue several jobs
  for user <- insert_list(5, :user) do
    Workers.SendEmail.new(%{user_id: user.id}) |> Oban.insert()
  end

  # Drain executes all available jobs in the queue
  assert %{success: 5, failure: 0} = Oban.drain_queue(queue: :notifications)
end

test "handles mixed success/failure" do
  Workers.Risky.new(%{will_fail: true}) |> Oban.insert()
  Workers.Risky.new(%{will_fail: false}) |> Oban.insert()

  result = Oban.drain_queue(queue: :default)
  assert result.success == 1
  assert result.failure == 1
end

# Drain with options
Oban.drain_queue(queue: :default, with_scheduled: true)  # Include scheduled jobs
Oban.drain_queue(queue: :default, with_recursion: true)   # Drain jobs enqueued by jobs
```

## Testing with Ecto.Multi

```elixir
test "job is only enqueued if transaction succeeds" do
  assert {:ok, _} =
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, valid_attrs))
    |> Oban.insert(:email, fn %{user: user} ->
      Workers.SendEmail.new(%{user_id: user.id})
    end)
    |> Repo.transaction()

  assert_enqueued worker: Workers.SendEmail
end

test "job is NOT enqueued if transaction fails" do
  assert {:error, :user, _, _} =
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, invalid_attrs))
    |> Oban.insert(:email, fn %{user: user} ->
      Workers.SendEmail.new(%{user_id: user.id})
    end)
    |> Repo.transaction()

  refute_enqueued worker: Workers.SendEmail
end
```

## Testing Unique Jobs

```elixir
test "deduplicates within uniqueness window" do
  args = %{user_id: 123, action: "sync"}

  assert {:ok, %Oban.Job{id: id1}} = Workers.SyncUser.new(args) |> Oban.insert()
  assert {:ok, %Oban.Job{id: id2}} = Workers.SyncUser.new(args) |> Oban.insert()

  # Same job returned (deduplicated)
  assert id1 == id2
end
```

## Testing Snooze and Retry

```elixir
test "snoozes when rate limited" do
  # Mock external service to return rate limit
  expect(ExternalServiceMock, :call, fn _ -> {:error, :rate_limited} end)

  assert {:snooze, 60} = perform_job(Workers.ExternalSync, %{id: 123})
end

test "retries on transient error" do
  expect(ExternalServiceMock, :call, fn _ -> {:error, :timeout} end)

  assert {:error, :timeout} = perform_job(Workers.ExternalSync, %{id: 123})
  # Job will be retried by Oban (up to max_attempts)
end
```

## Shared Test Helper

```elixir
# test/support/oban_helpers.ex
defmodule MyApp.ObanHelpers do
  use Oban.Testing, repo: MyApp.Repo

  def drain_all_queues do
    for queue <- [:default, :notifications, :imports, :webhooks] do
      Oban.drain_queue(queue: queue)
    end
  end

  def assert_job_enqueued(worker, args_subset) do
    assert_enqueued worker: worker, args: args_subset
  end
end
```
