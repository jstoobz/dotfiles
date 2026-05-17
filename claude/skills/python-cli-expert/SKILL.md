---
name: python-cli-expert
description: Python CLI patterns — typer apps, uv with PEP 723 inline deps, pytest, pathlib, atomic file writes, file locking, JSONL streaming, and production-grade stdlib idioms for command-line tools
targets:
  python: "3.11+"
  typer: "0.12+"
  uv: "0.4+"
  pytest: "8.0+"
  filelock: "3.13+"
---

# Python CLI Expert

## When to Use This Skill

- Building or extending a command-line tool in Python (single-file scripts, multi-subcommand apps, dispatcher binaries)
- Choosing how to ship dependencies (PEP 723 inline vs `pyproject.toml` + project mode)
- Writing safe filesystem code: atomic file writes, JSON read-modify-write under concurrent processes, JSONL streaming
- Writing pytest tests for a typer-based CLI (CliRunner, parametrize, monkeypatch, concurrency)
- Wiring exit codes, structured `--json` output, and shell-friendly streaming output (rich + stdlib logging)
- **Skip this skill for**: web frameworks (FastAPI/Flask/Django), data-science work (pandas/numpy/sklearn), heavy async (asyncio), or PyPI packaging. Those are different concerns.

## Mental Model

- **Typer is argparse + type hints.** You declare a function with typed args; typer derives the CLI surface. Don't fight it — let type hints do validation, let docstrings do help text.
- **Exit codes are the protocol.** A CLI is a function from `(argv, env, stdin) → (stdout, stderr, exit_code)`. Treat exit codes as a public contract, not a debugging afterthought. Calling skills, shell scripts, and CI all branch on them.
- **The filesystem is shared state.** If two processes can hit the same JSON/JSONL file simultaneously, you need a lock — even on a single-user laptop running parallel Claude sessions. "It only ran once before" is a bug timer, not a defense.
- **Atomic = write-tmp-then-rename.** `os.rename` (and `Path.rename`) is atomic on POSIX *within the same filesystem*. Writing in place corrupts on crash; writing to `/tmp` and renaming into the target directory can cross filesystems and become a non-atomic copy. Same-directory tmp file → rename.
- **`uv` removes the venv-management tax.** PEP 723 inline metadata lets a single `.py` file declare its deps and run via `uv run script.py` with zero install ceremony.

## Decision Tree: Dependencies and Packaging

```
What are you shipping?
├── Single .py file with a few deps, runs from a shebang or `uv run`? → PEP 723 inline deps
│   ├── Self-contained, no test suite alongside? → Stay single-file
│   └── Want tests via pytest? → Promote to project mode
├── Multi-module package with tests, CI, possibly multiple entry points? → pyproject.toml + uv project mode
│   ├── Many subcommands, dispatched by one wrapper? → Single `[project.scripts]` entry + typer subcommands
│   └── Tools meant for `pipx`/`uv tool install`? → Add `[project.scripts]` with explicit entry function
└── Vendoring deps into a repo for hermetic builds? → uv with locked `uv.lock` committed
```
For depth see [reference/uv-pep723.md](reference/uv-pep723.md).

## Decision Tree: File Locking

```
Two or more processes can touch the same file?
├── Read-only access? → No lock needed (POSIX reads are independent)
├── Single writer, many readers, writer rare? → Atomic rename is enough (readers see old or new, never partial)
├── Multiple writers, read-modify-write cycle? → REQUIRED: exclusive lock for the whole RMW
│   ├── Linux/macOS only, prefer stdlib? → `fcntl.flock` (advisory, OS-level)
│   ├── Need Windows / cross-platform? → `filelock` library (lock-file based, portable)
│   └── Want async or cross-machine (NFS)? → Out of scope; reach for a real lock service
└── Append-only writes, line-oriented (JSONL)? → `O_APPEND` is atomic for writes < PIPE_BUF; still lock for clean shutdown semantics
```
For the full RMW pattern see [reference/filesystem-patterns.md](reference/filesystem-patterns.md).

## Decision Tree: Running External Commands

```
Need to call another binary?
├── One-shot, want exit code + captured output? → subprocess.run(check=True, text=True, capture_output=True)
├── Streaming stdout as it's produced (long-running)? → subprocess.Popen + iterate stdout
├── Piping into stdin programmatically? → subprocess.run(..., input="text")
├── Want shell features (globs, pipes) intentionally? → shell=True with shlex.quote on inputs (rarely the right answer)
└── Hot loop / many short calls? → Reconsider — fork/exec is expensive; prefer a library call
```

## Core Patterns

### Typer skeleton (one-file CLI)

```python
#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12", "rich>=13"]
# ///
"""mytool — one-line description shown in --help."""
from __future__ import annotations
import typer
from rich.console import Console

app = typer.Typer(add_completion=True, no_args_is_help=True)
err = Console(stderr=True)

@app.command()
def hello(name: str = typer.Argument(..., help="Who to greet"),
          shout: bool = typer.Option(False, "--shout", help="Uppercase")) -> None:
    """Print a greeting."""
    msg = f"Hello, {name}"
    typer.echo(msg.upper() if shout else msg)

if __name__ == "__main__":
    app()
```
The shebang `#!/usr/bin/env -S uv run --quiet` makes the file directly executable; `uv` resolves inline deps on first run, caches them, then re-uses. For deeper typer patterns (subcommands, callbacks, completion, custom enums, rich integration) see [reference/typer-patterns.md](reference/typer-patterns.md).

### Exit-code convention (sysexits-style)

```python
import typer

# Constants — define once, import everywhere
EXIT_OK = 0          # success
EXIT_FAIL = 1        # operation failed; caller MUST abort
EXIT_WARN = 2        # operation succeeded with caveats; caller may continue
EXIT_USAGE = 3       # bad args / misuse; user error

# Use typer.Exit, NOT sys.exit — cleaner for CliRunner test isolation
if not config_path.exists():
    err.print(f"[red]config not found:[/] {config_path}")
    raise typer.Exit(code=EXIT_USAGE)
```
**Rule:** Pick a 0/1/2/3 scheme and document it in `--help`. Callers (shell scripts, other CLIs, CI) branch on the integer; "non-zero means bad" leaks information away from the caller that the integer would carry.

### `--json` output contract

```python
import json, sys

if json_mode:
    payload = {"id": new_id, "path": str(out_path), "status": "ok"}
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    raise typer.Exit(code=EXIT_OK)
```
Callers (other CLIs, shell pipelines) parse one JSON object per invocation. Document the schema in `--help`; treat it as a versioned contract — adding fields is safe, renaming or removing is breaking.

### ISO-8601 UTC timestamps

```python
from datetime import datetime, timezone

def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
# => "2026-05-17T14:32:08Z" — second precision, explicit Z suffix, no microseconds
```
**Rule:** Always UTC at the boundary; never persist naive (`tzinfo=None`) datetimes. The trailing `Z` is critical — without it, downstream parsers in other languages disagree on the zone.

### Atomic JSON read-modify-write with lock

```python
import json
from pathlib import Path
from filelock import FileLock

def update_manifest(path: Path, mutate) -> dict:
    lock = FileLock(str(path) + ".lock", timeout=10)
    with lock:
        data = json.loads(path.read_text()) if path.exists() else {}
        data = mutate(data)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
        tmp.replace(path)  # atomic on POSIX within same dir
        return data
```
The lock spans the entire RMW (read → mutate → write → rename). Releasing earlier creates a TOCTOU window where a sibling process can overwrite your read snapshot. See [reference/filesystem-patterns.md](reference/filesystem-patterns.md) for full discussion, including the write-ahead-log pattern (registration entry → durable artifact) — prior art: [PostgreSQL WAL](https://www.postgresql.org/docs/current/wal-intro.html), [journaling file systems](https://en.wikipedia.org/wiki/Journaling_file_system).

### Reading stdin without blocking on a TTY

```python
import sys

def read_stdin_or(default: str | None = None) -> str | None:
    if sys.stdin.isatty():
        return default          # interactive: no piped input
    return sys.stdin.read()
```
Without the `isatty()` check, an interactive invocation hangs waiting for EOF the user can't easily send. Always gate `stdin.read()` on `isatty()`.

### Graceful Ctrl-C

```python
def main() -> None:
    try:
        app()
    except KeyboardInterrupt:
        err.print("[yellow]aborted[/]")
        raise typer.Exit(code=130)  # 128 + SIGINT(2)
```
The `130` exit code is the shell convention for SIGINT; CI systems and shells branch on it.

## Anti-patterns

### Don't: write the canonical file in place

```python
# BAD — partial writes on crash corrupt the file
manifest.write_text(json.dumps(data))
```
**Why it bites:** A crash or kill mid-write leaves a truncated or zero-byte file. Every reader sees corruption until manual repair. Worse with JSON: a single missing `}` poisons every consumer.
**Instead:** Write `manifest.tmp` in the same directory, then `tmp.replace(manifest)`. See [reference/filesystem-patterns.md](reference/filesystem-patterns.md).

### Don't: slurp large JSONL files with `read_text().splitlines()`

```python
# BAD — loads the whole file into memory
lines = path.read_text().splitlines()
```
**Why it bites:** A `.jsonl` log that started at 1 KB grows to 100 MB+ over weeks. The slurp pattern works during dev, hangs in production. Every reader gets slower together as the file grows.
**Instead:** `for line in path.open(): ...` — streaming, constant memory.

### Don't: use bare `except:` or `except Exception:` without re-raising

```python
# BAD — swallows everything including KeyboardInterrupt
try:
    do_work()
except:
    pass
```
**Why it bites:** Hides bugs, eats Ctrl-C, makes debugging a guessing game. The CLI looks like it succeeded; the user has no idea work didn't happen.
**Instead:** Catch the specific exception you can recover from. Let everything else propagate; let the top-level handler convert to an exit code with a clear message.

### Don't: `sys.exit(1)` inside library functions

```python
# BAD — library function kills the process
def load_config(path: Path) -> dict:
    if not path.exists():
        sys.exit(1)
    ...
```
**Why it bites:** Untestable (every test that exercises the error path kills the test runner), uncomposable (no way to retry, recover, or wrap), and inconsistent (the caller may want a different exit code).
**Instead:** Raise an exception (custom `ConfigError` or stdlib `FileNotFoundError`); catch it at the typer command level and convert to `typer.Exit(code=...)`.

### Don't: `String.to_atom`-style — wait, wrong language. Don't: `eval`/`exec` on user input
Self-explanatory. Use `ast.literal_eval` for safe literals; reach for `json` or `argparse` for structured data.

## Common Gotchas

- **Naive datetimes silently drift.** `datetime.now()` (no tz) is in local time; persisted naive values misinterpret on read. Always `datetime.now(timezone.utc)`. Python 3.12+ deprecates `datetime.utcnow()` for exactly this reason.
- **`os.rename` across filesystems is `OSError: Invalid cross-device link`.** Tmp file MUST live in the same directory (same mount) as the target. `path.with_suffix(".tmp")` keeps it there; `tempfile.NamedTemporaryFile` defaults to `/tmp` which is often a separate filesystem.
- **`json.dump` without `sort_keys=True` produces non-deterministic output.** Git diffs become noisy across machines. Always pass `sort_keys=True, indent=2` for human-readable JSON; the cost is negligible.
- **`fcntl.flock` is Unix-only and advisory.** It only protects against processes that also call `flock`. A process that ignores it can still corrupt the file. `filelock` library wraps both `fcntl` (POSIX) and `msvcrt` (Windows) — prefer it for portability.
- **`subprocess.run(check=True)` raises `CalledProcessError`, which prints the command but NOT the captured stderr by default.** Add `text=True, capture_output=True` and inspect `e.stderr` in your handler — otherwise debugging "command failed" gives no signal.
- **`Path.glob("**/*")` follows symlinks by default.** Can loop forever on cyclic symlink trees. Use `Path.rglob` with explicit handling, or `os.walk(followlinks=False)` for safety.
- **typer's `--help` truncates docstrings at the first blank line in some terminal widths.** Keep the first line of a docstring as a complete one-line summary.
- **`uv run` caches inline deps in `~/.cache/uv/` keyed by content.** A changed `requires-python` or `dependencies` block re-resolves transparently; if a resolution looks stale, `uv cache clean` is the hammer.
- **`typer.echo` writes to stdout; `rich.print` to stderr is one extra import.** Mixing them in the same command means some output is captured by shells and some is not. Keep machine-readable on stdout, human-readable on stderr.
- **Pytest's `tmp_path` is per-test, `tmp_path_factory` is per-session.** Using `tmp_path_factory` carelessly leaks state between tests; default to `tmp_path` unless you explicitly need shared state.

## Quick Reference

```
Typer essentials:
  app = typer.Typer(no_args_is_help=True)
  @app.command()                          # register subcommand
  @app.callback()                         # global pre-command hook (e.g. --version)
  typer.Argument(..., help="...")         # positional, required
  typer.Option(default, "--flag/--no-flag")  # optional flag
  typer.Exit(code=N)                      # raise to exit with code
  typer.testing.CliRunner().invoke(app, ["sub", "--flag"])

uv / PEP 723:
  # /// script
  # requires-python = ">=3.11"
  # dependencies = ["typer>=0.12"]
  # ///
  uv run script.py                        # resolve + run
  uv run --with package script.py         # ad-hoc add a dep

Pathlib essentials:
  Path.home(), Path.cwd(), Path(__file__).parent
  path.read_text() / path.write_text(s)
  path.exists() / path.is_file() / path.is_dir()
  path.mkdir(parents=True, exist_ok=True)
  path.iterdir() / path.glob("*.json") / path.rglob("*.py")
  path.with_suffix(".tmp") / path.with_name("other.txt")
  tmp.replace(target)                     # atomic rename within same dir

Subprocess essentials:
  subprocess.run([bin, arg], check=True, text=True, capture_output=True)
  result.stdout / result.stderr / result.returncode
  subprocess.Popen([...], stdout=PIPE)    # for streaming output

Datetime / UUID:
  datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
  uuid.uuid4()                            # random
  str(uuid).lower()                       # normalized form

Pytest essentials:
  def test_x(tmp_path, monkeypatch, capsys): ...
  @pytest.mark.parametrize("a,b", [(1,2), (3,4)])
  monkeypatch.setattr(module, "name", value)
  monkeypatch.setenv("KEY", "val")
  monkeypatch.chdir(tmp_path)
  CliRunner().invoke(app, [...])
```

## When to Load Deeper References

- Building multi-subcommand apps, custom enums, callbacks, completion, rich tables/progress, or stdin handling beyond the basics? → Read [reference/typer-patterns.md](reference/typer-patterns.md)
- Writing pytest suites for a typer CLI, parametrizing tests, mocking subprocess, or proving lock correctness via concurrent processes? → Read [reference/pytest-patterns.md](reference/pytest-patterns.md)
- Choosing between PEP 723 inline deps and full `pyproject.toml` project mode, locking, or distribution? → Read [reference/uv-pep723.md](reference/uv-pep723.md)
- Designing atomic-write or RMW workflows, JSONL streaming, write-ahead-log patterns, or cross-platform file locking? → Read [reference/filesystem-patterns.md](reference/filesystem-patterns.md)
