---
name: liveview-expert
description: Phoenix LiveView patterns for stateful server-rendered UI including streams, async assigns, components, forms, uploads, and JS hooks
targets:
  elixir: "1.18+"
  phoenix: "1.8+"
  phoenix_live_view: "1.0+"
  otp: "27+"
---

# Phoenix LiveView Expert

## When to Use This Skill

- Editing a `.heex` template, `Phoenix.Component`, or `Phoenix.LiveComponent`
- Touching `mount/3`, `handle_event/3`, `handle_info/3`, or `handle_params/3`
- Working with `stream/3`, `assign_async/3`, or migrating away from `temporary_assigns`
- Setting up `live_session`, JS hooks, file uploads, or LiveView-side navigation
- Skip this skill when working on plain Phoenix controllers or JSON APIs (use `phoenix-expert`). For LiveView-specific test patterns (`Phoenix.LiveViewTest`, `render_click`, `has_element?`, `file_input`), see `elixir-testing-expert`.

## Mental Model

- **A LiveView is a long-lived process per user connection** — closer to a GenServer than a controller. State lives in the socket.
- **The server renders, the browser diffs** — there's no client-side framework. LiveView sends minimal DOM diffs over WebSocket.
- **Mount runs twice** — once for the initial HTTP render (cold), once after WebSocket upgrade (connected). Guard expensive work with `connected?(socket)`.
- **Reconnects lose process state** — anything you can't rebuild from the URL or DB belongs in the URL, the session, or the database. Not in process memory.

## Architecture / Request Flow

```
Initial HTTP request:
  Browser → GET /path → mount/3 (connected?: false) → render → static HTML

WebSocket upgrade:
  Browser ⇄ WS    → mount/3 (connected?: true)  → render → initial diff
                                                       ↓
                       handle_event / handle_info → render → DOM diff
                                                       ↓
                       handle_params (URL change) → render → DOM diff
```

## Decision Tree: Component vs LiveComponent vs LiveView

```
What kind of UI unit do you need?
├── Stateless markup reused across templates? → Phoenix.Component (function component)
├── Stateful, scoped to a parent LiveView, isolated event handling? → Phoenix.LiveComponent
│   └── Multiple instances need independent state? → LiveComponent with `:id`
├── Top-level page with its own URL and lifecycle? → Phoenix.LiveView (full LiveView)
└── Pure HTML helper with no assigns? → Plain function returning HEEx, no `Phoenix.Component`
```

## Decision Tree: Assigns Strategy for Collections

```
How should this list-shaped data live in the socket?
├── Small, bounded, fully replaced on update? → assign(:items, list)
├── Large list, append/prepend/delete operations? → stream(:items, list)
│   └── Need to reset (e.g. filter change)? → stream(:items, list, reset: true)
├── Loaded from DB on mount, expensive query? → assign_async(:items, fn -> ... end)
├── Streamed from external source over time? → stream + handle_info
└── Form data? → to_form(changeset) — NOT assign(:changeset, ...)
```

## Decision Tree: Where Does This State Belong?

```
Where should this piece of state live?
├── Survives reconnect, shareable via link? → URL params (handle_params + push_patch)
├── User identity, persists across LiveViews? → Session (mount via live_session)
├── Source of truth, queryable elsewhere? → Database (load in mount)
├── UI-only, ephemeral, lost on reconnect is fine? → Socket assigns
└── Cross-LiveView pub/sub? → Phoenix.PubSub (subscribe in mount, handle_info — see `phoenix-expert` for PubSub setup and topic conventions)
```

## Decision Tree: Navigation

```
What kind of transition?
├── Same LiveView, URL change only (filters, pagination)? → push_patch(to: ~p"/...")
│   └── Triggers handle_params/3 — no remount
├── Different LiveView in same live_session? → push_navigate(to: ~p"/...")
│   └── Remount, but keeps WS connection
├── Full page load (different live_session, leaves LV)? → redirect(to: ~p"/...")
└── In a HEEx template? → <.link patch={...}> / <.link navigate={...}>
```

## Core Patterns

### Function component (HEEx)

```elixir
defmodule MyAppWeb.CoreComponents do
  use Phoenix.Component

  attr :label, :string, required: true
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(disabled form name)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button type={@type} class="btn" {@rest}>
      {render_slot(@inner_block) || @label}
    </button>
    """
  end
end
```

**Rule:** Declare every assign with `attr` — runtime warnings catch typos and missing fields.

### LiveView skeleton

```elixir
defmodule MyAppWeb.UserLive.Index do
  use MyAppWeb, :live_view
  alias MyApp.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Accounts.subscribe()

    {:ok, stream(socket, :users, Accounts.list_users())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    {:ok, _} = Accounts.delete_user(user)
    {:noreply, stream_delete(socket, :users, user)}
  end

  @impl true
  def handle_info({:user_created, user}, socket) do
    {:noreply, stream_insert(socket, :users, user, at: 0)}
  end

  defp apply_action(socket, :index, _), do: assign(socket, :page_title, "Users")
  defp apply_action(socket, :new, _), do: assign(socket, :page_title, "New User")
end
```

### Streams for collections

```elixir
# Mount
{:ok, stream(socket, :posts, Posts.list())}

# Insert at top
stream_insert(socket, :posts, post, at: 0)

# Update in place (matches by dom_id)
stream_insert(socket, :posts, updated_post)

# Delete
stream_delete(socket, :posts, post)

# Replace entire stream (e.g., filter changed)
stream(socket, :posts, Posts.list(filter), reset: true)
```

```heex
<div id="posts" phx-update="stream">
  <div :for={{dom_id, post} <- @streams.posts} id={dom_id}>
    {post.title}
  </div>
</div>
```

**Rule:** Streams require `id="..."` on the container and `phx-update="stream"`. Each child needs `id={dom_id}`.

### Async assigns (non-blocking load)

```elixir
def mount(%{"id" => id}, _session, socket) do
  socket =
    socket
    |> assign(:id, id)
    |> assign_async(:user, fn ->
      case Accounts.get_user(id) do
        nil -> {:error, :not_found}
        user -> {:ok, %{user: user}}
      end
    end)

  {:ok, socket}
end
```

**Rule:** The function must return `{:ok, %{key: value}}` on success or `{:error, reason}` on failure. The `<.async_result>` `:failed` slot receives the error reason and renders accordingly.

```heex
<.async_result :let={user} assign={@user}>
  <:loading>Loading user...</:loading>
  <:failed :let={_reason}>Failed to load.</:failed>
  {user.name}
</.async_result>
```

### Forms

```elixir
def mount(_params, _session, socket) do
  changeset = Accounts.change_user(%User{})
  {:ok, assign(socket, :form, to_form(changeset))}
end

def handle_event("validate", %{"user" => params}, socket) do
  form =
    %User{}
    |> Accounts.change_user(params)
    |> Map.put(:action, :validate)
    |> to_form()

  {:noreply, assign(socket, :form, form)}
end

def handle_event("save", %{"user" => params}, socket) do
  case Accounts.create_user(params) do
    {:ok, user} ->
      {:noreply, socket |> put_flash(:info, "Created") |> push_navigate(to: ~p"/users/#{user}")}

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
```

```heex
<.form for={@form} phx-change="validate" phx-submit="save">
  <.input field={@form[:email]} type="email" label="Email" />
  <.input field={@form[:name]} label="Name" />
  <.button>Save</.button>
</.form>
```

**Rule:** Always use `to_form/1` — never `assign(:changeset, ...)`. The `Phoenix.HTML.Form` struct carries error/change state for `<.input>` to render correctly. (See `ecto-expert` for changeset construction, validation, and error helper patterns.)

### File uploads

```elixir
def mount(_, _, socket) do
  {:ok,
   socket
   |> assign(:uploaded_files, [])
   |> allow_upload(:avatar, accept: ~w(.jpg .png), max_entries: 1, max_file_size: 5_000_000)}
end

def handle_event("save", _params, socket) do
  uploaded =
    consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
      dest = Path.join("priv/static/uploads", Path.basename(path))
      File.cp!(path, dest)
      {:ok, "/uploads/#{Path.basename(dest)}"}
    end)

  {:noreply, update(socket, :uploaded_files, &(&1 ++ uploaded))}
end
```

```heex
<form phx-change="validate" phx-submit="save">
  <.live_file_input upload={@uploads.avatar} />
  <%= for entry <- @uploads.avatar.entries do %>
    <progress value={entry.progress} max="100" />
  <% end %>
</form>
```

### JS hooks (client-side interop)

```elixir
# In the template
<div id="map" phx-hook="Map" data-coords={Jason.encode!(@coords)}></div>
```

```javascript
// app.js
let Hooks = {}
Hooks.Map = {
  mounted() {
    this.map = initMap(JSON.parse(this.el.dataset.coords))

    // Server → client: receive events pushed from LiveView
    this.handleEvent("recenter", ({lat, lng}) => this.map.panTo([lat, lng]))

    // Client → server: send events that fire LiveView's handle_event/3
    this.map.on("click", (e) => {
      this.pushEvent("marker-clicked", {lat: e.latlng.lat, lng: e.latlng.lng})
    })
  },
  destroyed() { this.map.remove() }
}
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, ...})
```

```elixir
# Server → client
push_event(socket, "recenter", %{lat: 37.7, lng: -122.4})

# Client → server (handle_event/3 catches the pushEvent above)
def handle_event("marker-clicked", %{"lat" => lat, "lng" => lng}, socket) do
  {:noreply, assign(socket, :selected, {lat, lng})}
end
```

**Rule:** Hooks must have a unique `id` and a registered name in `Hooks` on the JS side. `mounted/updated/destroyed/disconnected/reconnected` are the lifecycle callbacks. Use `pushEvent` for client→server, `handleEvent` for server→client.

## Anti-patterns

### Don't: store large lists in regular assigns

```elixir
# BAD
def mount(_, _, socket) do
  {:ok, assign(socket, :posts, Posts.list_all())}  # 10,000 posts
end
```

**Why it bites:** Every assign lives in process memory, and *every* diff serializes through the WebSocket. A 10k-row list bloats the LiveView process and makes every update slow.

**Instead:**

```elixir
# GOOD
def mount(_, _, socket) do
  {:ok, stream(socket, :posts, Posts.list_all())}
end
```

Streams keep items in the DOM only — the server holds just the dom_id mapping.

### Don't: call the Repo from `render/1` or HEEx

```heex
<!-- BAD -->
<%= for post <- MyApp.Posts.list() do %>
  ...
<% end %>
```

**Why it bites:** `render/1` runs on every diff. You'll hammer the database on every assign change. There's also no error handling — a DB hiccup crashes the LiveView.

**Instead:** Load in `mount/3` (or `handle_event` if user-triggered) and assign the result. Render reads only from socket assigns.

### Don't: use `live_redirect` / `live_patch` helpers

```elixir
# BAD (deprecated)
<%= live_redirect "Users", to: Routes.user_index_path(@socket, :index) %>
```

**Why it bites:** Deprecated since LiveView 0.18 in favor of `<.link>` + verified routes. Old code keeps working but new code shouldn't compound the tech debt.

**Instead:**

```heex
<.link navigate={~p"/users"}>Users</.link>
<.link patch={~p"/users?page=2"}>Page 2</.link>
```

### Don't: store PIDs or refs in assigns

```elixir
# BAD
{:ok, pid} = Task.start_link(...)
assign(socket, :worker_pid, pid)
```

**Why it bites:** When the user reconnects (network blip, navigation), the LiveView remounts as a new process. Old PIDs are dead. Refs from `Process.monitor` are equally invalid.

**Instead:** Use `assign_async/3` for one-shot work, or have a separate supervised process keyed by user/session ID and look it up by name/Registry on mount.

## Common Gotchas

- **Mount runs twice** — once on HTTP (cold), once on WS connect. Guard expensive setup with `if connected?(socket), do: ...`. PubSub subscriptions belong inside the guard.
- **`temporary_assigns` is mostly superseded** — streams handle the "don't keep this in memory" use case better. Reach for `temporary_assigns` only for non-collection data you explicitly want to drop after render.
- **Stream updates don't reorder items** — `stream_insert/4` matches existing items by `dom_id` and updates them *in place*. If you want a freshly-updated post to jump to the top, you must `stream_delete` and `stream_insert(..., at: 0)`. There's no auto-sort by field — order is whatever you inserted.
- **`handle_params/3` fires on every URL change** including `push_patch` from the same LiveView. Don't put expensive work there without checking what actually changed.
- **HEEx attribute syntax: `:if` and `:for`** (since 0.18) is preferred over `<%= if/for %>`. Cleaner and more debuggable.
- **`~p` requires `Phoenix.VerifiedRoutes` import** — usually wired into `use MyAppWeb, :live_view`. If you get "undefined sigil ~p" you're missing the import.
- **`assign_new/3` for layouts and live_session** — use `assign_new(socket, :current_user, fn -> ... end)` so root layout and child LiveViews share assigns without re-fetching.
- **LiveComponent events bubble unless handled** — `handle_event` in a LiveComponent receives only events from its own DOM subtree. Send to parent with `send(self(), ...)` or `Phoenix.LiveView.send_update/2`.

## Quick Reference

```
LiveView lifecycle callbacks (in order on first connect):
  mount/3            (HTTP)         — connected?: false
  render/1                          — initial HTML
  mount/3            (WS upgrade)   — connected?: true
  handle_params/3                   — if URL has params
  render/1                          — reconciled diff

Per-event lifecycle:
  handle_event / handle_info / handle_params → render/1 → diff

Stream operations:
  stream/3            — initialize or reset (with reset: true)
  stream_insert/4     — add or update (matches by dom_id)
  stream_delete/3     — remove
  stream_delete_by_dom_id/3
```

## When to Load Deeper References

- Designing stream behavior (ordering, reset, dom_id, custom prefixes, batched inserts)? → Read `references/streams.md`
- Building nested forms, multi-step forms, or custom form input components? → Read `references/forms.md`
- Implementing direct-to-S3 uploads, image processing, or chunked upload UX? → Read `references/uploads.md`
- Writing JS hooks with complex lifecycle, push_event/handleEvent, or JS commands (`Phoenix.LiveView.JS`)? → Read `references/js-and-hooks.md`
- Testing LiveViews with `Phoenix.LiveViewTest` (`render_click`, `has_element?`, `file_input`, async tests)? → Read `references/testing.md`
