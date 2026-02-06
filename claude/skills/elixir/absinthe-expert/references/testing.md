# Absinthe Testing Reference

## Basic Query Test

```elixir
defmodule MyAppWeb.Schema.UserQueryTest do
  use MyApp.DataCase, async: true

  @get_user_query """
  query GetUser($id: ID!) {
    user(id: $id) {
      id
      email
      name
      role
    }
  }
  """

  test "returns user by id" do
    user = insert(:user, email: "alice@example.com", name: "Alice")

    assert {:ok, %{data: data}} =
      Absinthe.run(@get_user_query, MyAppWeb.Schema,
        variables: %{"id" => user.id},
        context: %{current_user: insert(:admin)}
      )

    assert data["user"]["email"] == "alice@example.com"
    assert data["user"]["name"] == "Alice"
  end

  test "returns null for nonexistent user" do
    assert {:ok, %{data: %{"user" => nil}, errors: errors}} =
      Absinthe.run(@get_user_query, MyAppWeb.Schema,
        variables: %{"id" => Ecto.UUID.generate()},
        context: %{current_user: insert(:admin)}
      )

    assert [%{message: "User not found"}] = errors
  end
end
```

## Mutation Test

```elixir
@create_user_mutation """
mutation CreateUser($input: CreateUserInput!) {
  createUser(input: $input) {
    id
    email
    name
  }
}
"""

test "creates user with valid input" do
  input = %{
    "email" => "new@example.com",
    "name" => "New User"
  }

  assert {:ok, %{data: %{"createUser" => data}}} =
    Absinthe.run(@create_user_mutation, MyAppWeb.Schema,
      variables: %{"input" => input},
      context: %{current_user: insert(:admin)}
    )

  assert data["email"] == "new@example.com"
  assert data["id"] != nil
end

test "returns validation errors" do
  input = %{"email" => "", "name" => ""}

  assert {:ok, %{errors: errors}} =
    Absinthe.run(@create_user_mutation, MyAppWeb.Schema,
      variables: %{"input" => input},
      context: %{current_user: insert(:admin)}
    )

  assert length(errors) > 0
end
```

## Testing with Auth Context

```elixir
# Helper for authenticated requests
defp run_query(query, variables \\ %{}, opts \\ []) do
  user = Keyword.get(opts, :as, insert(:admin))

  Absinthe.run(query, MyAppWeb.Schema,
    variables: variables,
    context: %{current_user: user}
  )
end

# Helper for unauthenticated requests
defp run_query_anon(query, variables \\ %{}) do
  Absinthe.run(query, MyAppWeb.Schema,
    variables: variables,
    context: %{}
  )
end

test "requires authentication" do
  assert {:ok, %{errors: [%{message: "Not authenticated"}]}} =
    run_query_anon(@protected_query)
end

test "requires admin role" do
  member = insert(:user, role: :member)

  assert {:ok, %{errors: [%{message: "Not authorized"}]}} =
    run_query(@admin_query, %{}, as: member)
end
```

## Testing Subscriptions

```elixir
defmodule MyAppWeb.Schema.SubscriptionTest do
  use MyAppWeb.SubscriptionCase

  @subscription """
  subscription PolicyUpdated($policyId: ID!) {
    policyUpdated(policyId: $policyId) {
      id
      status
    }
  }
  """

  test "receives policy update" do
    policy = insert(:policy)

    # Subscribe
    ref = push_doc(socket, @subscription,
      variables: %{"policyId" => policy.id}
    )
    assert_reply ref, :ok, %{subscriptionId: sub_id}

    # Trigger update
    Policies.update_policy(policy, %{status: :active})

    # Assert received
    assert_push "subscription:data", data
    assert data.result.data["policyUpdated"]["status"] == "active"
  end
end
```

## Testing with ConnCase (HTTP)

```elixir
defmodule MyAppWeb.GraphQL.UserTest do
  use MyAppWeb.ConnCase, async: true

  @query """
  query { users { id email } }
  """

  test "returns users via HTTP", %{conn: conn} do
    insert_list(3, :user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{generate_token(insert(:admin))}")
      |> post("/graphql", %{query: @query})

    assert %{"data" => %{"users" => users}} = json_response(conn, 200)
    assert length(users) == 3
  end
end
```

## Test Helper Module

```elixir
defmodule MyApp.AbsintheHelpers do
  @moduledoc "Helpers for Absinthe tests"

  def run(query, variables \\ %{}, context \\ %{}) do
    Absinthe.run(query, MyAppWeb.Schema,
      variables: stringify_keys(variables),
      context: context
    )
  end

  def run_authenticated(query, variables \\ %{}, user \\ nil) do
    user = user || MyApp.Factory.insert(:admin)
    run(query, variables, %{current_user: user})
  end

  # Assert successful query
  def assert_data(result, key) do
    assert {:ok, %{data: data}} = result
    assert data[key] != nil
    data[key]
  end

  # Assert error
  def assert_error(result, message) do
    assert {:ok, %{errors: errors}} = result
    assert Enum.any?(errors, &(&1.message =~ message))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end
  defp stringify_keys(other), do: other
end
```
