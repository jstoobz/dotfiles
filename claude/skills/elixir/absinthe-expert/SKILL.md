---
name: absinthe-expert
description: Absinthe GraphQL patterns including schema design, resolvers, middleware, Dataloader, and testing
---

# Absinthe Expert

## Architecture: Request Flow

```
HTTP Request → Phoenix Endpoint → Absinthe.Plug
  → Parse (query string → AST)
  → Validate (AST against schema)
  → Execute (resolve fields, run middleware)
  → Return JSON response
```

## Decision Tree: Resolver Patterns

```
What data operation?
├── Single entity by ID? → Resolver + Repo.get
├── List with filtering? → Resolver + Ecto query
├── Nested association? → Dataloader (ALWAYS for associations)
├── Mutation (write)? → Resolver + command dispatch
├── Computed/derived field? → Resolver function on type
├── N+1 potential? → Dataloader batch (never inline Repo calls)
├── Needs auth check? → Middleware before resolver
└── Subscription? → Subscription field + PubSub trigger
```

## Schema Design

```elixir
defmodule MyAppWeb.Schema do
  use Absinthe.Schema

  import_types MyAppWeb.Schema.Types.User
  import_types MyAppWeb.Schema.Types.Policy

  query do
    @desc "Get a user by ID"
    field :user, :user do
      arg :id, non_null(:id)
      resolve &MyAppWeb.Resolvers.Users.get_user/3
    end

    @desc "List users with filtering"
    field :users, list_of(:user) do
      arg :role, :user_role
      arg :active, :boolean, default_value: true
      resolve &MyAppWeb.Resolvers.Users.list_users/3
    end
  end

  mutation do
    field :create_user, :user do
      arg :input, non_null(:create_user_input)
      resolve &MyAppWeb.Resolvers.Users.create_user/3
    end
  end

  # Dataloader setup
  def context(ctx) do
    loader =
      Dataloader.new()
      |> Dataloader.add_source(MyApp.Accounts, MyApp.Accounts.data())

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults()]
  end
end
```

## Type Definitions

```elixir
defmodule MyAppWeb.Schema.Types.User do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  object :user do
    field :id, non_null(:id)
    field :email, non_null(:string)
    field :name, :string
    field :role, :user_role

    # Association via Dataloader (prevents N+1)
    field :organization, :organization, resolve: dataloader(MyApp.Accounts)
    field :posts, list_of(:post), resolve: dataloader(MyApp.Content)

    # Computed field
    field :display_name, :string do
      resolve fn user, _, _ ->
        {:ok, "#{user.first_name} #{user.last_name}"}
      end
    end
  end

  input_object :create_user_input do
    field :email, non_null(:string)
    field :name, non_null(:string)
    field :role, :user_role, default_value: :member
  end

  enum :user_role do
    value :admin, description: "Full access"
    value :member, description: "Standard access"
    value :viewer, description: "Read-only access"
  end
end
```

## Resolver Patterns

```elixir
defmodule MyAppWeb.Resolvers.Users do
  # Query resolver
  def get_user(_parent, %{id: id}, _resolution) do
    case MyApp.Accounts.get_user(id) do
      nil -> {:error, "User not found"}
      user -> {:ok, user}
    end
  end

  def list_users(_parent, args, _resolution) do
    {:ok, MyApp.Accounts.list_users(args)}
  end

  # Mutation resolver with auth context
  def create_user(_parent, %{input: input}, %{context: %{current_user: admin}}) do
    MyApp.Accounts.create_user(admin, input)
  end

  def create_user(_parent, _args, _resolution) do
    {:error, "Not authenticated"}
  end
end
```

## Middleware

```elixir
# Authentication middleware
defmodule MyAppWeb.Middleware.Authenticate do
  @behaviour Absinthe.Middleware

  def call(resolution, _config) do
    case resolution.context do
      %{current_user: _user} -> resolution
      _ -> Absinthe.Resolution.put_result(resolution, {:error, "Not authenticated"})
    end
  end
end

# Apply to fields
field :admin_data, :admin_data do
  middleware MyAppWeb.Middleware.Authenticate
  resolve &MyAppWeb.Resolvers.Admin.get_data/3
end

# Apply to all mutations
def middleware(middleware, _field, %{identifier: :mutation}) do
  [MyAppWeb.Middleware.Authenticate | middleware]
end
def middleware(middleware, _field, _object), do: middleware
```

## Dataloader

```elixir
# Source definition in context module
defmodule MyApp.Accounts do
  def data do
    Dataloader.Ecto.new(MyApp.Repo,
      query: &query/2
    )
  end

  # Customize queries per schema
  def query(User, params) do
    User
    |> maybe_filter_active(params)
    |> order_by([u], asc: u.name)
  end

  def query(queryable, _params), do: queryable
end

# In schema types — resolves via batch loading
field :users, list_of(:user), resolve: dataloader(MyApp.Accounts)

# With args
field :active_users, list_of(:user) do
  resolve dataloader(MyApp.Accounts, :users, args: %{active: true})
end
```

## Error Formatting

```elixir
# Changeset errors → GraphQL errors
defmodule MyAppWeb.Schema.Helpers do
  def format_changeset_errors(%Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)

    {:error, message: "Validation failed", details: errors}
  end
end
```

## Testing

```elixir
defmodule MyAppWeb.Schema.UserTest do
  use MyApp.DataCase, async: true

  @query """
  query GetUser($id: ID!) {
    user(id: $id) {
      id
      email
      name
    }
  }
  """

  test "returns user by id" do
    user = insert(:user, email: "test@example.com")

    assert {:ok, %{data: %{"user" => data}}} =
      Absinthe.run(@query, MyAppWeb.Schema,
        variables: %{"id" => user.id},
        context: %{current_user: insert(:admin)}
      )

    assert data["email"] == "test@example.com"
  end

  test "returns error for missing user" do
    assert {:ok, %{errors: [%{message: "User not found"}]}} =
      Absinthe.run(@query, MyAppWeb.Schema,
        variables: %{"id" => Ecto.UUID.generate()},
        context: %{current_user: insert(:admin)}
      )
  end
end
```

## References

- `references/schema-patterns.md` — Complex types, Relay connections, custom scalars, interfaces
- `references/testing.md` — Query/mutation test helpers, subscription testing, context setup
