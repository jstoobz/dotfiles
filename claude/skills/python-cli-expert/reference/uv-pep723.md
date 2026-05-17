# uv + PEP 723 Reference

Deep dive on dependency management for Python CLIs — when to use [PEP 723](https://peps.python.org/pep-0723/) inline script metadata vs full `pyproject.toml` + [uv](https://docs.astral.sh/uv/) project mode.

## Decision: Inline (PEP 723) vs Project Mode

| Property | PEP 723 inline | Project mode (`pyproject.toml`) |
|---|---|---|
| File count | 1 (`script.py`) | Many (`pyproject.toml`, `src/`, `tests/`, `uv.lock`) |
| Where deps live | `# /// script` block at top of the file | `[project.dependencies]` in `pyproject.toml` |
| How deps resolve | First `uv run script.py`; cached per content-hash | `uv sync` resolves into `.venv/`; locked in `uv.lock` |
| Test suite | Awkward (tests need their own dep declaration) | Native — `pytest` + `[project.optional-dependencies]` |
| Multi-module imports | Single file — no internal imports | `src/pkg/`, `pkg.submod` works as expected |
| CI cache | Per-script cache; usually fine | `uv.lock` enables reproducible installs |
| Distribution | `chmod +x script.py` + shebang | `uv tool install`, `pipx`, or PATH symlink |

**Rule of thumb:** if you'd want a `tests/` directory, use project mode. If you'd just `git add foo.py` and walk away, use inline.

## PEP 723: Inline Dependencies

```python
#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "typer>=0.12",
#     "rich>=13",
#     "filelock>=3.13",
# ]
# ///
"""Single-file CLI. Run as `./script.py` or `uv run script.py`."""
import typer

app = typer.Typer()

@app.command()
def hello(name: str) -> None:
    typer.echo(f"Hello, {name}")

if __name__ == "__main__":
    app()
```

**Key shebang trick:** `#!/usr/bin/env -S uv run --quiet` makes the script directly executable. The `-S` flag to `env` lets you pass arguments through to the interpreter (`-S` is GNU + macOS `env` >= 11.6 — both BSD and GNU coreutils support it now).

**Specifying versions:**

```python
# dependencies = [
#     "typer>=0.12,<1.0",           # range
#     "rich==13.7.1",                # pinned
#     "requests~=2.31",              # compatible release (>=2.31, <3.0)
#     "git+https://github.com/owner/repo@v1.2",  # git URL
# ]
```

**Running:** `uv run script.py [args]`. First run resolves and caches; subsequent runs use the cache.

**Cache invalidation:** uv hashes the `# /// script` block. Changes to `dependencies` or `requires-python` re-resolve transparently. To force-clear: `uv cache clean`.

## Project Mode: `pyproject.toml`

```toml
# pyproject.toml
[project]
name = "mytool"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "typer>=0.12",
    "filelock>=3.13",
]

[project.scripts]
mytool = "mytool.__main__:app"

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=5.0",
    "mypy>=1.10",
    "ruff>=0.5",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.pytest.ini_options]
testpaths = ["mytool/tests"]
pythonpath = ["."]
addopts = "-ra --strict-markers"

[tool.ruff]
line-length = 100
target-version = "py311"
```

**Workflow:**

```bash
uv venv                       # creates .venv/
uv sync --extra dev           # installs runtime + dev deps, writes uv.lock
uv run pytest                 # runs in the venv
uv run mytool register foo    # executes [project.scripts] entry
```

**Locking:** `uv.lock` is the reproducible-build artifact. Commit it to the repo. CI runs `uv sync --frozen` to install exactly the locked versions.

**Tool install (PATH binary):**

```bash
uv tool install --from . mytool
# Now `mytool` is on PATH (in ~/.local/bin or platform equivalent)
```

## Common Foot-guns

- **PEP 723 needs `uv >= 0.4` (or another PEP 723 runner like `pipx run`).** Older `uv` won't see the metadata. Document the minimum version in your README.
- **The `# /// script` block must use `#` line comments, not `"""`.** It's a structured TOML inside comment markers; one wrong character and `uv` parses it as plain code with no deps. After editing, run the script once to verify it still resolves.
- **`uv run` adds the script's directory to `sys.path` *only* in project mode.** For PEP 723 single-files, internal imports across multiple files don't work — that's the line where you outgrow inline.
- **`uv tool install` and `uv pip install` are different.** `tool install` creates an isolated venv per tool (like pipx); `pip install` installs into the active environment. For CLIs meant to be on PATH, you want `tool install`.
- **Forgetting `requires-python` makes uv pick an old version.** Some users have Python 3.8 as default; without `requires-python = ">=3.11"` your `str | None` syntax breaks for them silently. Always declare.
- **`uv.lock` is *not* a `requirements.txt`.** It's a richer format with resolution metadata. Don't pip-install from it; use `uv sync --frozen`.
- **Editable installs in project mode:** `uv pip install -e .` works inside a uv-managed venv, but `uv sync` doesn't auto-editable. For local-development workflows where you want `import mytool` to pick up your edits live, `uv sync` already does this — the package source is the working tree.
- **Mixing `requirements.txt` and `pyproject.toml` is a smell.** Pick one. If you need both for legacy CI, generate `requirements.txt` from `pyproject.toml` via `uv pip compile pyproject.toml -o requirements.txt`.
- **`uv cache prune` (smart cleanup) vs `uv cache clean` (nuclear).** Reach for `prune` first — it removes unused entries while keeping recent caches warm.

## When PEP 723 Fits

- One-shot ops scripts (`backup_db.py`, `migrate_keys.py`)
- Bootstrap binaries that wrap a typer app and dispatch into a sibling package (e.g. `bin/mytool` as a 10-line entrypoint that imports the real package)
- Throwaway analysis scripts that need a couple deps
- Examples in documentation that should be runnable as-is

## When Project Mode Fits

- Anything with a test suite
- Multi-module code (`pkg/cli.py`, `pkg/common.py`, `pkg/storage.py`)
- Tools meant to be installed (`uv tool install`, `pipx install`, etc.)
- CI-tested code where reproducibility matters (the `uv.lock` is the contract)
- Anything where you'd want type-checker config, ruff config, or coverage config in a `pyproject.toml`

## The hybrid: PEP 723 wrapper over a project-mode package

A common shape: a single-file `bin/mytool` with PEP 723 inline deps for *bootstrap-only* (typer itself), which then imports a sibling Python package that does the real work.

```python
#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12", "filelock>=3.13"]
# ///
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from mytool.__main__ import app
if __name__ == "__main__":
    app()
```

This gets you:
- Zero-install for end-users (just need `uv`)
- A real Python package with tests, type checking, refactor-friendly imports
- One single file to symlink onto PATH (`ln -s bin/mytool ~/.local/bin/mytool`)

For testing the package, the `pyproject.toml` runs the show; the `bin/mytool` wrapper is a thin shim.

## Cross-References

- For typer-side patterns of the entrypoint, see [typer-patterns.md](typer-patterns.md).
- For testing the package, see [pytest-patterns.md](pytest-patterns.md).
