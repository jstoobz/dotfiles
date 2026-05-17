# Typer Patterns Reference

Deep dive on [typer](https://typer.tiangolo.com/) — multi-subcommand apps, args, callbacks, completion, rich integration, stdin handling, and testing-friendly structure.

## Subcommand Dispatcher (the `mytool <verb>` pattern)

The dominant pattern for CLIs that grow: one entrypoint, multiple verbs (cf. `git`, `gh`, `docker`, `cargo`, `kubectl`).

```python
# mytool/__main__.py
from __future__ import annotations
import typer

app = typer.Typer(
    name="mytool",
    help="My tool — short one-line description.",
    no_args_is_help=True,
    add_completion=True,
    pretty_exceptions_show_locals=False,  # don't leak env in tracebacks
)

# Register subcommands from sibling modules
from . import register, publish
app.add_typer(register.app, name="register")
app.add_typer(publish.app, name="publish")

if __name__ == "__main__":
    app()
```

```python
# mytool/register.py
import typer

app = typer.Typer(help="Register a new entry.")

@app.callback(invoke_without_command=True)
def register(
    name: str = typer.Argument(..., help="Entry name"),
    force: bool = typer.Option(False, "--force", help="Overwrite if exists"),
    json_out: bool = typer.Option(False, "--json", help="Emit structured output"),
) -> None:
    """..."""
    ...
```

**Why `add_typer` over `@app.command` for subcommands:** lets each subcommand live in its own module with its own `Typer()` instance, its own callbacks, and its own tests. Reachable as `mytool register foo` once registered.

## Argument Types

```python
@app.command()
def cmd(
    # Positional, required
    name: str = typer.Argument(..., help="The thing's name"),

    # Positional, with default
    count: int = typer.Argument(1, help="How many"),

    # Optional flag (--shout / --no-shout)
    shout: bool = typer.Option(False, "--shout/--no-shout"),

    # Optional with short flag
    verbose: int = typer.Option(0, "-v", "--verbose", count=True, help="Repeat for more"),

    # Path validation — typer checks existence at parse time
    config: Path = typer.Option(..., exists=True, file_okay=True, dir_okay=False, readable=True),

    # Choice via Enum
    mode: Mode = typer.Option(Mode.normal, case_sensitive=False),

    # Multiple values (repeated flag)
    tags: list[str] = typer.Option([], "--tag", help="Repeat for multiple tags"),

    # Hidden flag (omitted from --help)
    debug: bool = typer.Option(False, "--debug", hidden=True),

    # Reads from env var if not passed
    api_key: str = typer.Option(..., envvar="API_KEY"),
) -> None:
    ...
```

The `Argument(...)` / `Option(...)` first arg is the default. `...` (literal Ellipsis) means *required*. Path constraints (`exists`, `readable`, etc.) move filesystem validation into the parser.

## Custom Enums for Choice Validation

```python
from enum import Enum

class LogLevel(str, Enum):
    debug = "debug"
    info = "info"
    warn = "warn"
    error = "error"

@app.command()
def serve(level: LogLevel = typer.Option(LogLevel.info, "--log-level")) -> None:
    """`--log-level` accepts only one of: debug, info, warn, error."""
    typer.echo(f"running at {level.value}")
```

**Rule:** Use `class X(str, Enum)` — typer compares against `.value` strings, and the `str` mixin makes them format/serialize cleanly. Plain `Enum` (no `str` mixin) breaks JSON serialization.

## Exit Codes

```python
EXIT_OK, EXIT_FAIL, EXIT_WARN, EXIT_USAGE = 0, 1, 2, 3

@app.command()
def cmd(target: Path) -> None:
    if not target.exists():
        typer.secho(f"not found: {target}", fg=typer.colors.RED, err=True)
        raise typer.Exit(code=EXIT_USAGE)
    try:
        do_work(target)
    except DurabilityError as e:
        typer.secho(f"durability failure: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(code=EXIT_FAIL)
    except StaleSnapshotWarning as e:
        typer.secho(f"warn: {e}", fg=typer.colors.YELLOW, err=True)
        raise typer.Exit(code=EXIT_WARN)
```

**Rule:** Always `raise typer.Exit(code=N)` over `sys.exit(N)`. typer's exit unwinds cleanly through the framework and is easy to assert on in `CliRunner.invoke(...).exit_code`.

## Global Callback (--version, --debug)

```python
def version_callback(value: bool) -> None:
    if value:
        typer.echo(f"mytool {__version__}")
        raise typer.Exit()

@app.callback()
def main(
    version: bool = typer.Option(
        False, "--version", callback=version_callback, is_eager=True,
        help="Show version and exit.",
    ),
    debug: bool = typer.Option(False, "--debug", envvar="MYTOOL_DEBUG"),
) -> None:
    """mytool — short description."""
    # Stash debug on a module-level context for subcommands to read.
```

`is_eager=True` makes `--version` run before any subcommand parsing. Use it for any flag that should short-circuit the whole app (`--version`, `--help-extended`).

## Shell Completion

```python
app = typer.Typer(add_completion=True)
```

That single flag wires `--install-completion` and `--show-completion` automatically. Users run `mytool --install-completion zsh` once; future tab-completion comes for free. No further code needed.

## Reading stdin (piped input)

```python
import sys

@app.command()
def write(
    content_file: Path | None = typer.Option(None, "--content-file", exists=True),
    content_stdin: bool = typer.Option(False, "--content-stdin"),
) -> None:
    if content_file:
        content = content_file.read_text()
    elif content_stdin:
        if sys.stdin.isatty():
            typer.echo("--content-stdin given but stdin is a TTY", err=True)
            raise typer.Exit(code=EXIT_USAGE)
        content = sys.stdin.read()
    else:
        typer.echo("provide --content-file or --content-stdin", err=True)
        raise typer.Exit(code=EXIT_USAGE)
    ...
```

**Rule:** Always gate `sys.stdin.read()` on `not sys.stdin.isatty()`. Otherwise interactive invocations hang on EOF the user can't easily send.

## Rich Integration

```python
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

out = Console()           # stdout — for machine-friendly when piped
err = Console(stderr=True)  # stderr — for human-friendly status

# Tables
def render_entries(entries: list[dict]) -> None:
    table = Table(title="Entries")
    table.add_column("ID", style="cyan")
    table.add_column("Created", style="dim")
    table.add_column("Status")
    for e in entries:
        table.add_row(e["id"], e["created_at"], e["status"])
    out.print(table)

# Progress (use sparingly — noisy in CI logs)
with Progress(SpinnerColumn(), TextColumn("{task.description}"), transient=True) as p:
    task = p.add_task("indexing...", total=None)
    do_slow_thing()
```

**Rule:** Machine-readable output (JSON, lists meant for piping) → stdout. Human-readable status / progress → stderr. Mixing them poisons `cmd | jq` because half the output is captured and half isn't.

**Detecting non-TTY:** `Console(stderr=True).is_terminal` is `False` when piped or redirected; rich auto-disables color in that case, but if you need to short-circuit progress spinners or fancy output, branch on `out.is_terminal`.

## Comparison: typer vs alternatives

| Library | Strength | When to choose |
|---|---|---|
| **typer** | Type-hint-driven, terse, modern, built on `click` | Default for any new CLI. ~3-line skeleton for one command. |
| **click** | Mature, huge ecosystem, decorators | When you need a click-only plugin or library that already extends click. |
| **argparse** (stdlib) | Zero deps, ships everywhere | Single-file tools where adding a dep is overkill — e.g. a one-off ops script with `uv` unavailable. |
| **fire** | Auto-generates CLI from any object/function | Quick-and-dirty exploration; not for production CLIs (poor help generation, surprising flag parsing). |

For multi-subcommand CLI tools: typer. The type-hint discipline doubles as inline documentation.

## Common Foot-guns

- **`@app.callback(invoke_without_command=True)` is required to make the root command runnable without a subcommand.** Without it, `mytool` (no args) errors out asking for a subcommand. Set `no_args_is_help=True` on `Typer()` to instead show help — usually the better UX.
- **typer infers help text from the function docstring AND parameter `help=` strings.** Mixing both works; the docstring fills the command description, `help=` fills the per-arg help. Empty docstring → cryptic command description.
- **`bool` flags with no `"--no-X"` half default to `--X` only.** `typer.Option(False, "--debug")` enables `--debug` but no `--no-debug`. To get both, use `"--debug/--no-debug"`.
- **`list[str]` with default `[]` is dangerously shared across invocations in some patterns.** typer creates a fresh list per call, but if you mutate it, write defensively. Prefer `tuple[str, ...]` for "really should be immutable" or `list[str] = typer.Option([], ...)`.
- **`pretty_exceptions_show_locals=True` (typer default) prints local variables in tracebacks.** Leaks env vars, secrets, file paths into logs. Always disable in production CLIs: `Typer(pretty_exceptions_show_locals=False)`.
- **`typer.echo` is fine; `typer.secho` adds color but writes to stdout by default.** Pass `err=True` to send colored output to stderr (the usual destination for warnings/errors).
- **`raise typer.Exit()` (no code) is exit code 0, not 1.** Surprising for users coming from `sys.exit()` where bare-call defaults to 0 too — but worth re-stating because the typer docs sometimes show `raise typer.Exit()` in error paths.
- **Adding `@app.command()` without parens registers the function as a command literally named `app`.** The parens are not optional: `@app.command()`. typer doesn't warn — you'll just see your command missing from `--help`.
- **`Path` args don't auto-`resolve()` symlinks.** If your code compares paths, call `path.resolve()` explicitly or accept that `~/foo` and `/Users/me/foo` may compare unequal.

## Testing typer apps

See [pytest-patterns.md](pytest-patterns.md) for the testing companion — `CliRunner`, exit-code assertions, stdin injection, and concurrency tests for file-locked commands.
