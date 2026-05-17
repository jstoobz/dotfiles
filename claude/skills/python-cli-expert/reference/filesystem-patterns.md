# Filesystem Patterns Reference

Deep dive on `pathlib`, atomic writes, file locking, JSONL streaming, and the write-ahead-log pattern for artifacts. Patterns that survive concurrent processes, crashes, and growth from KB to GB.

## `pathlib` over `os.path`

```python
from pathlib import Path

# Construction
root = Path.home() / ".local" / "share" / "myapp"
config = Path(__file__).parent / "config.toml"
cwd = Path.cwd()

# Querying
path.exists() / path.is_file() / path.is_dir() / path.is_symlink()
path.stat().st_size / path.stat().st_mtime
path.suffix / path.stem / path.name / path.parent

# I/O
path.read_text(encoding="utf-8") / path.write_text(s, encoding="utf-8")
path.read_bytes() / path.write_bytes(b)
with path.open("r") as f: ...           # stream

# Mutation
path.mkdir(parents=True, exist_ok=True)
path.unlink(missing_ok=True)            # delete file (3.8+)
path.rmdir()                            # only if empty
path.rename(new_path) / path.replace(new_path)
path.chmod(0o644)

# Traversal
path.iterdir()                          # immediate children
path.glob("*.json")                     # one-level pattern
path.rglob("**/*.py")                   # recursive
```

**Rule:** `pathlib` is the API; `os.path` is the legacy. The only common reason to drop to `os.*` is a syscall not exposed on `Path` (e.g. `os.replace` *is* exposed as `Path.replace`, but `os.makedev` is not).

## Atomic File Writes

The pattern: write to a tmp file *in the same directory* as the target, then rename. POSIX guarantees rename within a filesystem is atomic — readers see either the old file or the new file, never partial content.

```python
from pathlib import Path

def atomic_write_text(path: Path, content: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)   # atomic; overwrites target if it exists
```

**`replace` vs `rename`:**

| Method | Behavior on existing target |
|---|---|
| `Path.rename(target)` | Errors on Windows if target exists; POSIX overwrites silently |
| `Path.replace(target)` | Overwrites on both — *use this for atomic writes* |

**Why tmp must live in the same directory:**

```python
# BAD — /tmp is often a separate filesystem (tmpfs)
import tempfile
with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
    f.write(content)
    Path(f.name).replace(target)   # OSError: Invalid cross-device link
```

The fix:

```python
# GOOD — tmp in same dir
tmp = target.with_name(target.name + ".tmp")
# or: tempfile.NamedTemporaryFile(dir=target.parent, ...)
```

**Add `fsync` for crash durability:**

```python
import os

def atomic_write_text_fsync(path: Path, content: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())     # force kernel buffer to disk
    tmp.replace(path)
    # Optional: also fsync the directory to persist the rename
    dir_fd = os.open(str(path.parent), os.O_RDONLY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)
```

**When to fsync:** anything where a power failure or kernel crash mid-write would lose data the user already considers "written" (database, manifest of in-flight work). For most CLIs writing markdown notes, skip the fsync — the kernel flushes on its own schedule and the cost (synchronous disk I/O) is measurable.

## File Locking for Concurrent RMW

Two processes both read JSON, both mutate, both write back. Without a lock, the second write clobbers the first's mutation — the classic read-modify-write race.

### `filelock` library (portable, recommended)

```python
from filelock import FileLock
from pathlib import Path
import json

def update_manifest(path: Path, mutate) -> dict:
    """Read manifest, apply `mutate`, write back atomically under exclusive lock."""
    lock = FileLock(str(path) + ".lock", timeout=10)
    with lock:
        data = json.loads(path.read_text()) if path.exists() else {}
        data = mutate(data)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
        tmp.replace(path)
    return data
```

The lock spans the entire RMW. Releasing earlier creates a TOCTOU (time-of-check / time-of-use) window where a sibling process can overwrite your read snapshot.

### `fcntl.flock` (stdlib, POSIX-only)

```python
import fcntl
from pathlib import Path

def update_manifest_flock(path: Path, mutate) -> dict:
    path.touch(exist_ok=True)
    with path.open("r+") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            content = f.read()
            data = json.loads(content) if content.strip() else {}
            data = mutate(data)
            new = json.dumps(data, indent=2, sort_keys=True)
            # Can't atomic-rename while file is held open under flock;
            # truncate-and-rewrite in place is acceptable for small files held under lock
            f.seek(0)
            f.write(new)
            f.truncate()
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    return data
```

### Comparison

| Property | `fcntl.flock` | `filelock` library |
|---|---|---|
| Platform | POSIX only (Linux, macOS, BSD) | Cross-platform (uses `fcntl` on POSIX, `msvcrt` on Windows) |
| Dep | stdlib | `pip install filelock` |
| Advisory? | Yes — only protects processes that also call `flock` | Same (advisory, not mandatory) |
| Lock file vs file itself | Locks the file | Uses a sidecar `.lock` file |
| Context manager | Manual; pair `LOCK_EX` / `LOCK_UN` | `with FileLock(...):` |
| NFS / network filesystems | Unreliable | Equally unreliable — use a real lock service |

**Recommendation:** Use `filelock` for portability and ergonomics; reach for `fcntl` only if a stdlib-only constraint exists.

## Write-Ahead-Log Pattern for Artifacts

A registration pattern: **write a small index entry before the durable artifact**, so any reader sees in-flight work without waiting for ceremony completion.

```python
def write_artifact_durable_first(
    artifact_path: Path,
    content: str,
    ledger_path: Path,
    session_id: str,
) -> None:
    # 1. REGISTRATION write — append entry to the ledger first (cheap, fast, atomic)
    register_in_ledger(ledger_path, {
        "session_id": session_id,
        "artifact": artifact_path.name,
        "status": "pending",
        "created_at": now_iso(),
    })
    # 2. DURABLE write — write the artifact under exclusive lock
    atomic_write_text(artifact_path, content)
    # 3. COMMIT — mark the ledger entry committed (idempotent)
    mark_ledger_committed(ledger_path, session_id, artifact_path.name)
```

**Why this ordering:** if the durable write fails or the process crashes, the ledger entry is still there and recovery tooling can find the in-flight work. If we wrote the artifact first and the ledger entry second, a crash between them produces an *unregistered* artifact — invisible to every reader that consults the ledger.

**Prior art:**

- [PostgreSQL WAL](https://www.postgresql.org/docs/current/wal-intro.html) — the canonical database implementation: log records precede page mutations; replicas and recovery consult the log
- [Write-ahead logging (Wikipedia)](https://en.wikipedia.org/wiki/Write-ahead_logging) — the general technique
- [Journaling file systems](https://en.wikipedia.org/wiki/Journaling_file_system) — ext4, NTFS, APFS journal metadata before applying it
- [Two-phase commit](https://en.wikipedia.org/wiki/Two-phase_commit_protocol) — the distributed-systems cousin

**When this applies:**

- "Ceremony-archived" workflows: create now, commit later
- Multi-process workflows where one party needs to see another's in-flight state
- Tools where listing/searching should reflect in-flight, not just settled, state
- Anywhere crash-loss of in-flight work is unacceptable

**When it doesn't:**

- Truly ephemeral artifacts (logs, scratch)
- Synchronous single-process workflows with no in-flight window
- Systems where the ceremony IS the creation (`git commit` is itself atomic)

## JSONL: Stream, Don't Slurp

```python
# BAD — loads entire file into memory; hangs as the JSONL grows
import json
data = [json.loads(line) for line in path.read_text().splitlines()]

# GOOD — constant memory; works on a 100MB JSONL
def iter_jsonl(path: Path):
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)
```

**Append a row atomically:**

```python
def append_jsonl(path: Path, row: dict) -> None:
    line = json.dumps(row, sort_keys=True) + "\n"
    # O_APPEND on POSIX is atomic for writes smaller than PIPE_BUF (4096 bytes typical).
    # For larger rows or strict semantics, hold a lock around the append.
    with path.open("a", encoding="utf-8") as f:
        f.write(line)
```

**Filter without loading the file:**

```python
def find_session(path: Path, session_id: str) -> dict | None:
    for record in iter_jsonl(path):
        if record.get("session_id") == session_id:
            return record
    return None
```

## Common Foot-guns

- **`os.rename` across filesystems raises `OSError: Invalid cross-device link`.** Keep tmp in the target's parent directory. `/tmp` is frequently a separate `tmpfs` mount.
- **`Path.rename` is *not* an atomic-overwrite on Windows.** Use `Path.replace` for cross-platform atomic-overwrite semantics.
- **`json.dump` without `sort_keys=True` produces non-deterministic byte output.** Diffs become noisy across runs/machines. Always pass `sort_keys=True, indent=2` for files humans read.
- **`fcntl.flock` is advisory.** A process that ignores it can still corrupt the file. The discipline only protects against participating processes.
- **NFS and other network filesystems break `flock` in subtle ways.** If two machines might write to the same file, you need a real lock service (Consul, Zookeeper, Redis SETNX, etc.) — file locks won't save you.
- **`Path.glob("**/*")` follows symlinks by default and can loop forever on cyclic links.** For untrusted directory trees, walk manually with `os.walk(followlinks=False)`.
- **`Path.read_text()` defaults to `locale.getpreferredencoding()`.** On systems with non-UTF-8 locales, this corrupts unicode. Always pass `encoding="utf-8"` explicitly.
- **`tempfile.NamedTemporaryFile` deletes on close by default.** Pair with `delete=False` if you need the file to outlive the `with` block (e.g. to rename it).
- **`shutil.move` is `rename` if same filesystem else `copy + delete`.** The non-atomic copy fallback defeats atomic-write semantics. Use `Path.replace` when atomicity matters.
- **`json.loads("")` raises `JSONDecodeError`, not returning `None` or `{}`.** Guard empty / nonexistent files: `data = json.loads(content) if content.strip() else {}`.
- **`Path.stat().st_mtime` is a float of seconds since epoch.** Mixing with `int(time.time())` gives off-by-fractional-seconds bugs. Use `.st_mtime_ns` (int nanoseconds) when comparing times for "modified since X."

## Quick Reference

```
Atomic write pattern:
  tmp = target.with_name(target.name + ".tmp")
  tmp.write_text(content, encoding="utf-8")
  tmp.replace(target)

Locked RMW:
  with FileLock(str(target) + ".lock", timeout=10):
      data = json.loads(target.read_text()) if target.exists() else {}
      data = mutate(data)
      atomic_write_text(target, json.dumps(data, indent=2, sort_keys=True))

JSONL stream:
  with path.open("r") as f:
      for line in f:
          if line.strip():
              yield json.loads(line)

JSONL append:
  with path.open("a") as f:
      f.write(json.dumps(row, sort_keys=True) + "\n")
```
