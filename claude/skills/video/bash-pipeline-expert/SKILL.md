---
name: bash-pipeline-expert
description: Bash patterns for multi-stage media pipelines — CLI binary structure, idempotent stage artifacts, jq JSON consumption, dependency checking, parallel jobs, and cross-platform shims for macOS/Linux.
---

# Bash Pipeline Expert

## Mental Model

The pipeline is a **binary tool** — like ffmpeg or ImageMagick. Users install it, point it at their project, and call commands. No code lives inside the tool.

```
bin/tool <command> <config> [flags]
    ↓
core/<command>.sh       ← bash: media processing (ffmpeg/ImageMagick)
engine/plan.py          ← Python: config parsing + timing logic
.build/                 ← intermediate artifacts (idempotent, skippable)
output/                 ← final deliverables
```

The Python engine owns YAML config and emits JSON. Bash scripts consume JSON via `jq` and call ffmpeg/ImageMagick. The boundary is hard — bash never reads YAML.

## Quick Reference

| I need to... | Use |
|---|---|
| Structure a CLI binary dispatcher | `→ references/cli-and-install.md` |
| Write an install script | `→ references/cli-and-install.md` |
| Make a stage idempotent (skip if done) | `→ references/stage-patterns.md` |
| Resume pipeline from a failed step | `→ references/stage-patterns.md` |
| Read plan.json fields in bash | `→ references/json-and-jq.md` |
| Iterate over JSON arrays in bash | `→ references/json-and-jq.md` |
| Run ffmpeg jobs in parallel with a cap | `→ references/stage-patterns.md` |
| Handle BSD vs GNU date/stat differences | `→ references/cross-platform.md` |
| Check required dependencies at startup | `→ references/cross-platform.md` |

## Must-Know Gotchas

| Issue | Fix |
|---|---|
| `bc` aliased on macOS | Use `/usr/bin/bc` explicitly |
| BSD `date` rejects GNU `-d` flag | `date -j -f '%Y-%m-%d' ...` on macOS |
| `stat` flags differ BSD/GNU | Use `stat -f%z` (macOS) or `stat -c%s` (Linux) with OS detection |
| `sips` macOS-only | Guard with `command -v sips` and fall back to `magick` |
| `shopt -s nullglob` | Add to every script — prevents literal `*.jpg` when no match |
| `set -euo pipefail` | Add to every script — catches unset vars and pipe failures |
| Glob expands before function call | Quote all paths: `process_file "$f"` not `process_file $f` |
| `printf '%.6f'` on `bc` output | Prevents scientific notation in ffmpeg filter args |
| Background jobs and `set -e` | Use `wait $pid || { log "job failed"; exit 1; }` not bare `wait` |

## Script Header (Every Pipeline Script)

```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
```

`BASH_SOURCE[0]` resolves correctly whether the script is called directly or sourced.

## References

- `references/cli-and-install.md` — binary dispatcher pattern, install script, PATH setup, help output
- `references/stage-patterns.md` — idempotent stages, `.build/` artifacts, skip logic, parallel jobs with concurrency cap
- `references/json-and-jq.md` — reading plan.json, iterating arrays, extracting nested values, building JSON in bash
- `references/cross-platform.md` — macOS/Linux shims, OS detection, dependency version checking
