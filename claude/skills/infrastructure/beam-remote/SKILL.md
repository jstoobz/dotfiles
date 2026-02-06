---
name: beam-remote
description: Use when needing to connect to a running Elixir/BEAM node via AWS ECS exec for live inspection and debugging. Triggers on "connect to the node", "check running processes", "inspect memory", "remote console", "ECS exec", "check the node", or any live BEAM debugging request.
---

# Live BEAM Node Introspection

Connect to running Elixir/BEAM nodes via AWS ECS exec for read-only inspection and debugging.

## SAFETY RULES (READ FIRST)

**Default mode: READ-ONLY.** All inspection commands are safe. Mutations require explicit user confirmation.

| Category                   | Examples                                                                                                                        | Permission                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **SAFE** (read-only)       | `:erlang.memory()`, `:recon.proc_count/2`, `Process.info/2`, `:sys.get_state/1`, Ecto selects, `:ets.info/1`, `:ets.tab2list/1` | Auto-allowed                                                  |
| **CAUTION** (side effects) | `:erlang.garbage_collect/1`, `:sys.trace/2`, `:erlang.system_flag/2`                                                            | Warn user, proceed if acknowledged                            |
| **DANGEROUS** (mutations)  | `Repo.insert/update/delete`, `GenServer.cast/2`, `:init.stop/0`, `Process.exit/2`                                               | **BLOCK — require explicit user confirmation before running** |

See `references/safety-guardrails.md` for full classification and confirmation gate templates.

## Arguments

`/beam-remote <env>`

| Argument | Values                                          | Notes                           |
| -------- | ----------------------------------------------- | ------------------------------- |
| `<env>`  | Environment name (e.g., `qa`, `uat`, `staging`) | Adapt to your AWS profile names |

## Connection Workflow

### 1. Authenticate to AWS

```bash
# Check if already authenticated
aws sts get-caller-identity --profile <env>

# If expired:
aws sso login --profile <env>
```

### 2. Find Running Tasks

```bash
aws ecs list-tasks \
  --cluster <CLUSTER_NAME> \
  --service-name <SERVICE_NAME> \
  --profile <env>
```

### 3. Connect to Container

```bash
aws ecs execute-command \
  --cluster <CLUSTER_NAME> \
  --task <TASK_ID> \
  --container <CONTAINER_NAME> \
  --interactive \
  --command "/bin/bash" \
  --profile <env>
```

### 4. Attach to Elixir Node

```bash
/app/bin/<app_name> remote
```

**To exit**: `Ctrl+C` twice (safe disconnect). **Never** use `:init.stop()` — it kills the node.

### 5. Verify BEAM Configuration

```bash
# Before attaching, check VM args
ps aux | grep beam
# Look for: -S 4:4 (schedulers), -SDcpu 4, -SDio 10, -sname
```

## Quick Health Check

Paste this block for a comprehensive snapshot (requires `:recon`):

```elixir
alias MyApp.Repo
import Ecto.Query

health = %{
  timestamp: DateTime.utc_now(),
  memory: :erlang.memory() |> Enum.map(fn {k, v} -> {k, Float.round(v / 1_048_576, 2)} end) |> Enum.into(%{}),
  process_count: length(Process.list()),
  process_limit: :erlang.system_info(:process_limit),
  port_count: length(Port.list()),
  port_limit: :erlang.system_info(:port_limit),
  ets_table_count: length(:ets.all()),
  top_memory_pids: :recon.proc_count(:memory, 5) |> Enum.map(fn {pid, mem, info} -> %{pid: inspect(pid), memory_mb: Float.round(mem / 1_048_576, 2), info: info} end),
  top_mailbox_pids: :recon.proc_count(:message_queue_len, 5) |> Enum.map(fn {pid, len, info} -> %{pid: inspect(pid), queue_len: len, info: info} end),
  oban_available: Repo.one(from j in Oban.Job, where: j.state == "available", select: count(j.id)),
  oban_executing: Repo.one(from j in Oban.Job, where: j.state == "executing", select: count(j.id)),
  oban_discarded: Repo.one(from j in Oban.Job, where: j.state == "discarded", select: count(j.id))
}

IO.inspect(health, pretty: true, limit: :infinity)
```

## Investigation Routing

```
What are you investigating?
├── Memory issues → :recon.proc_count(:memory, N), :recon.bin_leak(N)
├── Process issues → :recon.proc_count(:message_queue_len, N), Process.info/2
├── Scheduler saturation → :recon.scheduler_usage(5000)
├── ETS growth → ETS table analysis snippet
├── GenServer state → :sys.get_state/1
└── Full health check → Quick health check block above
```

For detailed investigation playbooks, see `references/investigation-playbooks.md`.

## Common One-Liners

```elixir
# Memory overview (MB)
:erlang.memory() |> Enum.map(fn {k, v} -> {k, Float.round(v / 1_048_576, 2)} end)

# Top 10 processes by memory
:recon.proc_count(:memory, 10)

# Top 10 processes by mailbox length
:recon.proc_count(:message_queue_len, 10)

# Binary memory leak detection
:recon.bin_leak(10)

# Scheduler utilization (5-second sample)
:recon.scheduler_usage(5000)

# Is the system overloaded?
:erlang.system_info(:process_count) > 100_000 or :erlang.memory(:total) > 14_000_000_000

# Process count by initial call (find spawners)
Process.list()
|> Enum.map(&Process.info(&1, :initial_call))
|> Enum.frequencies()
|> Enum.sort_by(&elem(&1, 1), :desc)
|> Enum.take(10)
```

## Troubleshooting Connection

| Error                            | Cause                               | Fix                                            |
| -------------------------------- | ----------------------------------- | ---------------------------------------------- |
| AccessDeniedException            | IAM role lacks `ecs:ExecuteCommand` | Use profile with write/exec access             |
| Session Manager plugin not found | Missing AWS plugin                  | Install from AWS docs                          |
| Container not responding         | Container OOM or unhealthy          | Try other task, check `aws ecs describe-tasks` |
| Remote console hangs             | Node overwhelmed                    | Try another task in the HA pair                |
