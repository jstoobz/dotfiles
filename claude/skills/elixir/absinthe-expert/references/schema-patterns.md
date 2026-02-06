# Absinthe Schema Patterns Reference

## Custom Scalars

```elixir
# JSON scalar
scalar :json, name: "JSON" do
  serialize fn value -> value end
  parse fn
    %Absinthe.Blueprint.Input.String{value: value} -> Jason.decode(value)
    %Absinthe.Blueprint.Input.Null{} -> {:ok, nil}
    _ -> :error
  end
end

# DateTime scalar
scalar :datetime, name: "DateTime" do
  serialize fn dt -> DateTime.to_iso8601(dt) end
  parse fn
    %Absinthe.Blueprint.Input.String{value: value} -> DateTime.from_iso8601(value)
    _ -> :error
  end
end

# Money scalar (Decimal)
scalar :money, name: "Money" do
  serialize fn d -> Decimal.to_string(d) end
  parse fn
    %Absinthe.Blueprint.Input.String{value: value} -> {:ok, Decimal.new(value)}
    %Absinthe.Blueprint.Input.Float{value: value} -> {:ok, Decimal.from_float(value)}
    %Absinthe.Blueprint.Input.Integer{value: value} -> {:ok, Decimal.new(value)}
    _ -> :error
  end
end
```

## Relay-Style Connections (Pagination)

```elixir
# Define connection type
connection node_type: :user do
  field :total_count, :integer
  edge do
    field :cursor, :string
  end
end

# In query
field :users, type: :user_connection do
  arg :first, :integer, default_value: 10
  arg :after, :string
  arg :filter, :user_filter
  resolve &Resolvers.Users.list_users_connection/3
end

# Resolver
def list_users_connection(_parent, args, _resolution) do
  users = Accounts.list_users_paginated(args)
  Absinthe.Relay.Connection.from_query(
    users,
    &Repo.all/1,
    args
  )
end
```

## Interfaces and Unions

```elixir
# Interface — shared fields
interface :node do
  field :id, non_null(:id)
  resolve_type fn
    %User{}, _ -> :user
    %Policy{}, _ -> :policy
    _, _ -> nil
  end
end

object :user do
  interface :node
  field :id, non_null(:id)
  field :email, :string
end

# Union — either/or types
union :search_result do
  types [:user, :policy, :invoice]
  resolve_type fn
    %User{}, _ -> :user
    %Policy{}, _ -> :policy
    %Invoice{}, _ -> :invoice
  end
end

field :search, list_of(:search_result) do
  arg :query, non_null(:string)
  resolve &Resolvers.Search.search/3
end
```

## Input Object Patterns

```elixir
# Nested input
input_object :create_policy_input do
  field :name, non_null(:string)
  field :effective_date, non_null(:date)
  field :coverage, :coverage_input
  field :pricing_options, list_of(:pricing_option_input)
end

input_object :coverage_input do
  field :type, non_null(:coverage_type)
  field :limit, :money
  field :deductible, :money
end

# Filter input
input_object :user_filter do
  field :role, :user_role
  field :active, :boolean
  field :search, :string
  field :created_after, :datetime
end
```

## Subscriptions

```elixir
# In schema
subscription do
  field :policy_updated, :policy do
    arg :policy_id, non_null(:id)

    config fn args, _resolution ->
      {:ok, topic: "policy:#{args.policy_id}"}
    end

    trigger :update_policy, topic: fn policy ->
      "policy:#{policy.id}"
    end
  end
end

# Trigger from resolver
def update_policy(_parent, %{input: input}, _resolution) do
  case Policies.update_policy(input) do
    {:ok, policy} ->
      Absinthe.Subscription.publish(
        MyAppWeb.Endpoint,
        policy,
        policy_updated: "policy:#{policy.id}"
      )
      {:ok, policy}
    error -> error
  end
end
```

## Context and Auth Setup

```elixir
# In Plug (before Absinthe)
defmodule MyAppWeb.Plugs.AbsintheContext do
  def init(opts), do: opts

  def call(conn, _opts) do
    context = build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

  defp build_context(conn) do
    %{current_user: conn.assigns[:current_user]}
  end
end

# In Schema
def context(ctx) do
  loader =
    Dataloader.new()
    |> Dataloader.add_source(Accounts, Accounts.data())
    |> Dataloader.add_source(Policies, Policies.data())

  Map.put(ctx, :loader, loader)
end
```

## Error Handling Patterns

```elixir
# Resolver returns structured errors
def create_user(_parent, %{input: input}, _resolution) do
  case Accounts.create_user(input) do
    {:ok, user} -> {:ok, user}
    {:error, %Ecto.Changeset{} = cs} -> {:error, format_errors(cs)}
    {:error, :unauthorized} -> {:error, message: "Not authorized", code: "UNAUTHORIZED"}
    {:error, reason} -> {:error, reason}
  end
end

# Middleware for consistent error formatting
defmodule MyAppWeb.Middleware.ErrorHandler do
  @behaviour Absinthe.Middleware

  def call(resolution, _config) do
    %{resolution | errors: Enum.flat_map(resolution.errors, &format_error/1)}
  end

  defp format_error(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, messages} ->
      %{message: "#{field}: #{Enum.join(messages, ", ")}", field: field}
    end)
  end

  defp format_error(error), do: [error]
end
```
