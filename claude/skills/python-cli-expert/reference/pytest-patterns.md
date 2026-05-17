# Pytest Patterns Reference

Deep dive on testing Python CLIs with [pytest](https://docs.pytest.org/) — fixtures, parametrize, monkeypatch, `CliRunner` for typer apps, and concurrent-process tests for file-locked code.

## Project Layout

```
mytool/
├── __init__.py
├── __main__.py
├── register.py
├── common.py
└── tests/
    ├── conftest.py            # shared fixtures
    ├── test_register.py
    └── test_common.py
```

Place tests *inside* the package or in a sibling `tests/` directory. `pytest --rootdir=mytool` picks them up. Add `[tool.pytest.ini_options]` to `pyproject.toml` for pythonpath and test discovery:

```toml
[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["mytool/tests"]
addopts = "-ra --strict-markers"
```

## The Three Fixtures You Reach for First

| Fixture | What it gives | Use it when |
|---|---|---|
| `tmp_path` | A `Path` to a fresh temp dir, deleted after the test | Any test that touches the filesystem |
| `monkeypatch` | Scope-safe attribute / env / cwd patching, auto-undone | Patching `subprocess.run`, env vars, `sys.argv`, modules |
| `capsys` | Captures stdout/stderr; `.readouterr()` returns `(out, err)` | Asserting on printed output, log lines, JSON emitted to stdout |

```python
def test_writes_atomic(tmp_path: Path, monkeypatch, capsys) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("MYTOOL_DATA_DIR", str(tmp_path / "data"))

    do_thing()

    captured = capsys.readouterr()
    assert "ok" in captured.out
    assert (tmp_path / "data" / "manifest.json").exists()
```

## conftest.py — Shared Fixtures

```python
# mytool/tests/conftest.py
from __future__ import annotations
import json
from pathlib import Path
import pytest

@pytest.fixture
def data_root(tmp_path: Path, monkeypatch) -> Path:
    """Isolated MYTOOL_DATA_DIR for the test, pre-seeded with empty manifest."""
    root = tmp_path / "data"
    (root / "entries").mkdir(parents=True)
    (root / "manifest.json").write_text("{}")
    monkeypatch.setenv("MYTOOL_DATA_DIR", str(root))
    return root

@pytest.fixture
def sample_jsonl(tmp_path: Path, monkeypatch) -> Path:
    """Pre-seed a JSONL log with one record for streaming tests."""
    f = tmp_path / "events.jsonl"
    f.write_text(json.dumps({
        "id": "00000000-0000-0000-0000-000000000001",
        "timestamp": "2026-01-01T00:00:00Z",
        "event": "hello",
    }) + "\n")
    monkeypatch.chdir(tmp_path)
    return f
```

**Rule:** Fixtures *compose*. `data_root` and `sample_jsonl` are independent; a test taking both gets both. Don't merge them into a mega-fixture.

## Scope Rules

```python
@pytest.fixture                    # default: function scope (per test)
@pytest.fixture(scope="module")    # one instance per .py file
@pytest.fixture(scope="session")   # one instance per pytest invocation
```

**Rule:** Default to function scope. Wider scopes are an optimization — and a footgun: state leaks between tests, and `monkeypatch` is function-scoped so wider-scoped fixtures can't use it directly. Reach for module scope only when setup is genuinely expensive (a DB schema, a long subprocess).

## Parametrize for Table-Driven Tests

```python
@pytest.mark.parametrize("input,expected", [
    ("user@example.com", True),
    ("no-at-sign", False),
    ("", False),
    ("  spaces  @example.com", False),
])
def test_validate_email(input: str, expected: bool) -> None:
    assert validate_email(input) is expected
```

Each row becomes a separate test in the report — granular pass/fail beats a single test with a for-loop, which stops at the first failure and leaves you guessing which row broke.

**Parametrize multiple args:**

```python
@pytest.mark.parametrize("a", [1, 2])
@pytest.mark.parametrize("b", ["x", "y"])
def test_combinations(a: int, b: str) -> None:
    ...   # runs 2 * 2 = 4 times
```

**Use `ids=` to name the cases:**

```python
@pytest.mark.parametrize("path,kind", [
    ("foo.txt", "file"),
    ("dir/", "dir"),
], ids=["plain-file", "trailing-slash-dir"])
def test_classify(path: str, kind: str) -> None: ...
```

## Mocking subprocess

```python
import subprocess

def test_calls_git(monkeypatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd, **kw):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout="main\n", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    branch = current_branch()

    assert calls == [["git", "rev-parse", "--abbrev-ref", "HEAD"]]
    assert branch == "main"
```

**Rule:** Patch at the *use site* — if your code does `from subprocess import run`, the patch must hit `mymodule.run`, not `subprocess.run`. Safer: `import subprocess` and call `subprocess.run(...)`, patch `subprocess.run`.

## Testing typer apps with CliRunner

```python
from typer.testing import CliRunner
from mytool.__main__ import app

runner = CliRunner()

def test_register_emits_json(data_root: Path) -> None:
    result = runner.invoke(app, ["register", "foo", "--json"])

    assert result.exit_code == 0
    payload = json.loads(result.stdout)
    assert payload["status"] == "ok"
    assert "id" in payload

def test_register_usage_error() -> None:
    result = runner.invoke(app, ["register"])  # missing required positional
    assert result.exit_code == 2  # typer's default for missing required args
    assert "missing argument" in result.stderr.lower()
```

**`CliRunner.invoke` returns a `Result`:**

| Attribute | Meaning |
|---|---|
| `result.exit_code` | The integer raised by `typer.Exit(code=...)` |
| `result.stdout` | Captured stdout |
| `result.stderr` | Captured stderr (only if `CliRunner(mix_stderr=False)`) |
| `result.exception` | The exception if one was raised (not `typer.Exit`) |
| `result.exc_info` | `(type, value, tb)` triple |

**Separate stderr capture:** by default typer's CliRunner *mixes* stderr into stdout. To assert on them independently:

```python
runner = CliRunner(mix_stderr=False)
```

**Pipe stdin programmatically:**

```python
result = runner.invoke(app, ["write-artifact", "--content-stdin"], input="hello\n")
```

## File-Locking Tests (concurrent processes)

Mocking doesn't prove a real lock works. Spawn actual subprocesses.

```python
import os, subprocess, sys, json
from pathlib import Path

def test_parallel_writes_dont_corrupt_manifest(tmp_path: Path) -> None:
    root = tmp_path / "data"
    (root / "entries").mkdir(parents=True)
    (root / "manifest.json").write_text("{}")

    env = {**os.environ, "MYTOOL_DATA_DIR": str(root)}

    # Spawn N concurrent `mytool register` processes
    procs = []
    for i in range(5):
        work = tmp_path / f"work-{i}"
        work.mkdir()
        procs.append(subprocess.Popen(
            [sys.executable, "-m", "mytool", "register", f"entry-{i}", "--json"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            cwd=str(work),
        ))
    results = [p.wait() for p in procs]

    assert all(rc == 0 for rc in results), "every concurrent register must succeed"
    # Manifest must still parse — no corruption from racing writers.
    manifest = json.loads((root / "manifest.json").read_text())
    assert isinstance(manifest, dict)
    # All five entries registered, none lost to a clobbering write.
    assert len(manifest.get("entries", {})) == 5
```

**Rule:** This is the test that catches a missing or broken file lock. Mocked tests pass without a lock; concurrent-process tests don't.

## Asserting on Captured Output

```python
def test_emits_json(capsys, data_root: Path) -> None:
    runner.invoke(app, ["register", "foo", "--json"])
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert payload["status"] == "ok"

def test_warns_to_stderr(capsys) -> None:
    do_thing_that_warns()
    captured = capsys.readouterr()
    assert "warning" in captured.err.lower()
    assert captured.out == ""  # nothing on stdout
```

**Rule:** Assert on stdout vs stderr separation. Tests that conflate them mask real bugs in CLI hygiene (machine output bleeding into human channels).

## Common Foot-guns

- **`tmp_path` is unique per test, `tmp_path_factory.mktemp("name")` is unique per call.** Sharing across tests via `tmp_path_factory` at session scope leaks state.
- **`monkeypatch.setattr("module.attr", value)` uses dotted-path string lookup, then mutates the attribute on that module object.** If your code does `from module import attr`, the import-time binding doesn't see the patch. Patch the *use site*, not the *definition site*.
- **`capsys` doesn't capture subprocess output.** Subprocesses get their own stdin/stdout/stderr. For subprocess output, use `capture_output=True` on `subprocess.run` and inspect `result.stdout/stderr`.
- **`CliRunner` defaults to `mix_stderr=True`.** Tests asserting `result.stderr` get `AttributeError` unless you pass `CliRunner(mix_stderr=False)` when constructing the runner.
- **`pytest.raises` without `match=` accepts any error message.** Use `match=r"expected pattern"` to assert message content; otherwise a misleading later exception silently passes the test.
- **Parametrize IDs default to the `repr` of the value.** Complex objects produce ugly IDs like `param0`. Always pass explicit `ids=[...]` for human-readable test reports.
- **Tests touching cwd MUST use `monkeypatch.chdir(tmp_path)`.** Without it, the next test inherits whatever cwd the previous one left, causing order-dependent flakes.
- **Async fixtures need `pytest-asyncio` plus an explicit `@pytest_asyncio.fixture` decorator.** Plain `@pytest.fixture` async functions silently don't await.
- **`pytest -x` stops at first failure; `pytest --ff` reruns failures first.** Useful combo for iterating on a flaky test: `pytest --ff -x`.
- **Test names matter — `test_<function-under-test>_<scenario>` is the convention.** `test_create_user_with_duplicate_email_returns_error` reads in failure output; `test_dupe` doesn't.

## Quick Reference

```
Common fixtures:
  tmp_path, tmp_path_factory       # filesystem
  monkeypatch                      # env, attrs, cwd, sys.argv
  capsys, capfd                    # capture stdout/stderr (capfd also captures fd-level)
  caplog                           # capture logging output
  request                          # access test metadata (request.node.name, etc.)

Marks:
  @pytest.mark.parametrize("a,b", [...])
  @pytest.mark.skip("reason")
  @pytest.mark.skipif(sys.platform == "win32", reason="POSIX only")
  @pytest.mark.xfail(reason="known bug")
  @pytest.mark.slow                # custom mark; register in pyproject.toml

CliRunner:
  runner = CliRunner(mix_stderr=False)
  result = runner.invoke(app, [...], input="...", env={...})
  result.exit_code / result.stdout / result.stderr / result.exception

Patching:
  monkeypatch.setattr(target, value)
  monkeypatch.setenv("KEY", "val") / monkeypatch.delenv("KEY", raising=False)
  monkeypatch.chdir(path)
  monkeypatch.syspath_prepend(path)
```
