# Advanced Ecto Queries Reference

## Dynamic Queries

```elixir
# Build queries dynamically from user input
def filter_users(params) do
  User
  |> maybe_filter_role(params["role"])
  |> maybe_filter_active(params["active"])
  |> maybe_filter_search(params["search"])
  |> Repo.all()
end

defp maybe_filter_role(query, nil), do: query
defp maybe_filter_role(query, role), do: where(query, [u], u.role == ^role)

defp maybe_filter_active(query, nil), do: query
defp maybe_filter_active(query, "true"), do: where(query, [u], u.active == true)
defp maybe_filter_active(query, "false"), do: where(query, [u], u.active == false)

defp maybe_filter_search(query, nil), do: query
defp maybe_filter_search(query, term) do
  search = "%#{term}%"
  where(query, [u], ilike(u.name, ^search) or ilike(u.email, ^search))
end
```

### Dynamic Field Selection

```elixir
import Ecto.Query

def sort_by_field(query, field, direction) when field in ~w(name email inserted_at)a do
  field = String.to_existing_atom(field)
  order = [{direction, dynamic([u], field(u, ^field))}]
  order_by(query, ^order)
end
```

## Named Bindings

```elixir
# Named bindings make complex queries readable
def users_with_active_policies(query) do
  from u in query,
    join: p in assoc(u, :policies),
    as: :policy,
    where: p.status == :active
end

def policies_in_state(query, state) do
  where(query, [policy: p], p.state == ^state)
end

# Compose them:
User
|> users_with_active_policies()
|> policies_in_state(:approved)
|> Repo.all()
```

## Window Functions

```elixir
# Rank users by activity within their organization
from u in User,
  join: a in Activity, on: a.user_id == u.id,
  group_by: [u.id, u.organization_id],
  select: %{
    user_id: u.id,
    activity_count: count(a.id),
    rank: over(row_number(), partition_by: u.organization_id, order_by: [desc: count(a.id)])
  }
```

## Common Table Expressions (CTEs)

```elixir
# Recursive CTE for hierarchical data
recursive_query =
  "categories"
  |> where([c], is_nil(c.parent_id))
  |> select([c], %{id: c.id, name: c.name, depth: 0})
  |> union_all(
    ^from(c in "categories",
      join: ct in "category_tree", on: ct.id == c.parent_id,
      select: %{id: c.id, name: c.name, depth: ct.depth + 1}
    )
  )

from "category_tree"
|> with_cte("category_tree", as: ^recursive_query)
|> select([ct], ct)
|> Repo.all()
```

## Subqueries

```elixir
# Users with more than 5 posts
active_authors =
  from p in Post,
    group_by: p.user_id,
    having: count(p.id) > 5,
    select: p.user_id

from u in User,
  where: u.id in subquery(active_authors)

# Subquery in select
from u in User,
  select: %{
    name: u.name,
    post_count: subquery(
      from(p in Post, where: p.user_id == parent_as(:user).id, select: count())
    )
  },
  as: :user
```

## Lateral Joins

```elixir
# Get latest 3 posts per user (top-N per group)
latest_posts =
  from p in Post,
    where: p.user_id == parent_as(:user).id,
    order_by: [desc: p.inserted_at],
    limit: 3,
    select: p

from u in User,
  as: :user,
  lateral_join: p in subquery(latest_posts),
  on: true,
  select: {u.name, p.title}
```

## Aggregation Patterns

```elixir
# Multiple aggregates in one query
from p in Post,
  group_by: p.status,
  select: %{
    status: p.status,
    count: count(p.id),
    avg_length: avg(fragment("length(?)", p.body)),
    latest: max(p.inserted_at)
  }

# Conditional aggregation
from o in Order,
  select: %{
    total: count(o.id),
    completed: count(fragment("CASE WHEN ? = 'completed' THEN 1 END", o.status)),
    revenue: sum(fragment("CASE WHEN ? = 'completed' THEN ? END", o.status, o.total))
  }
```

## Fragment for Raw SQL

```elixir
# Use fragment for PostgreSQL-specific features
from u in User,
  where: fragment("? @> ?", u.tags, ^["admin"]),  # Array contains
  where: fragment("? BETWEEN ? AND ?", u.created_at, ^start_date, ^end_date),
  select: %{
    name: u.name,
    initials: fragment("LEFT(?, 1) || LEFT(split_part(?, ' ', 2), 1)", u.name, u.name)
  }

# JSONB queries
from p in Post,
  where: fragment("?->>'category' = ?", p.metadata, ^"tech")
```

## Upsert Patterns

```elixir
# Insert or update on conflict
Repo.insert(
  changeset,
  on_conflict: {:replace, [:name, :updated_at]},
  conflict_target: :email
)

# Insert or do nothing
Repo.insert(changeset, on_conflict: :nothing, conflict_target: :external_id)

# Bulk upsert
Repo.insert_all(
  User,
  users_list,
  on_conflict: {:replace, [:name, :updated_at]},
  conflict_target: :email
)
```

## Pagination

```elixir
# Offset-based (simple but slow for large offsets)
def paginate(query, page, per_page) do
  offset = (page - 1) * per_page
  from q in query, limit: ^per_page, offset: ^offset
end

# Cursor-based (efficient for large datasets)
def after_cursor(query, nil), do: query
def after_cursor(query, cursor_id) do
  where(query, [r], r.id > ^cursor_id)
end

def fetch_page(query, cursor, limit) do
  results =
    query
    |> after_cursor(cursor)
    |> order_by([r], asc: r.id)
    |> limit(^(limit + 1))
    |> Repo.all()

  has_next = length(results) > limit
  items = Enum.take(results, limit)
  next_cursor = if has_next, do: List.last(items).id

  %{items: items, has_next: has_next, cursor: next_cursor}
end
```
