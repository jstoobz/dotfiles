# CLI Binary & Install Patterns

## The Dispatcher Pattern

`bin/<tool>` is a thin router — no logic, just dispatch to `core/` scripts:

```bash
#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-}"
CONFIG="${2:-}"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> <config.yml> [options]

Commands:
  intake    Scan and index project assets
  plan      Compute timing and emit build plan (dry-run safe)
  render    Build segments, acts, and final video
  package   Bundle output files and generate manifest
  all       Run intake → plan → render → package in sequence

Options:
  --dry-run    Print planned operations without executing
  --from STEP  Resume pipeline from this step (intake|plan|render|package)
  --force      Re-run step even if artifacts already exist

EOF
    exit "${1:-0}"
}

[[ -z "$CMD" ]] && usage
[[ -z "$CONFIG" ]] && { echo "Error: config file required"; usage 1; }
[[ -f "$CONFIG" ]] || { echo "Error: config not found: $CONFIG"; exit 1; }

shift 2   # remaining args passed through to subcommand

case "$CMD" in
    intake)  exec "$TOOL_ROOT/core/intake.sh"  "$CONFIG" "$@" ;;
    plan)    exec "$TOOL_ROOT/core/plan.sh"    "$CONFIG" "$@" ;;
    render)  exec "$TOOL_ROOT/core/render.sh"  "$CONFIG" "$@" ;;
    package) exec "$TOOL_ROOT/core/package.sh" "$CONFIG" "$@" ;;
    all)
        "$TOOL_ROOT/core/intake.sh"  "$CONFIG" "$@"
        "$TOOL_ROOT/core/plan.sh"    "$CONFIG" "$@"
        "$TOOL_ROOT/core/render.sh"  "$CONFIG" "$@"
        "$TOOL_ROOT/core/package.sh" "$CONFIG" "$@"
        ;;
    help|--help|-h) usage ;;
    *) echo "Unknown command: $CMD"; usage 1 ;;
esac
```

- `exec` replaces the shell process for single commands (avoids extra process)
- `shift 2` passes remaining flags to subcommands so `--dry-run` works everywhere
- `[[ -f "$CONFIG" ]]` validates before dispatch, not per-script

---

## Install Script

Users run: `curl -fsSL https://example.com/install.sh | bash`

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/you/tool"
INSTALL_DIR="${HOME}/.local/bin"
TOOL_DIR="${HOME}/.local/share/tool"
VERSION="${VERSION:-latest}"

echo "Installing tool..."

# Download release or clone
if command -v git &>/dev/null; then
    if [[ -d "$TOOL_DIR" ]]; then
        git -C "$TOOL_DIR" pull --quiet
    else
        git clone --depth 1 "$REPO" "$TOOL_DIR"
    fi
else
    echo "Error: git is required for installation"
    exit 1
fi

# Link binary
mkdir -p "$INSTALL_DIR"
ln -sf "$TOOL_DIR/bin/tool" "$INSTALL_DIR/tool"
chmod +x "$TOOL_DIR/bin/tool"

# PATH check
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo ""
    echo "  Add to your shell profile:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo "Done. Run: tool --help"
```

---

## Resolving Config-Relative Paths

`config.yml` paths are relative to the config file's directory, not the working directory:

```bash
CONFIG="$1"
PROJECT_ROOT="$(cd "$(dirname "$CONFIG")" && pwd)"
CONFIG_ABS="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"

# Then all asset paths resolve against PROJECT_ROOT:
CONTENT_DIR="${PROJECT_ROOT}/content"
BUILD_DIR="${PROJECT_ROOT}/.build"
```

This lets users call the tool from any working directory:
```bash
tool render ~/projects/my-wedding/config.yml
tool render ./config.yml
```

---

## Consistent Logging

Define once in a shared lib (`core/lib.sh`), source in every script:

```bash
# core/lib.sh
log()     { echo -e "\n\033[1;36m▸ $*\033[0m"; }
success() { echo -e "\033[1;32m  ✓ $*\033[0m"; }
warn()    { echo -e "\033[1;33m  ⚠ $*\033[0m" >&2; }
error()   { echo -e "\033[1;31m  ✗ $*\033[0m" >&2; exit 1; }
```

```bash
# In each core script:
# shellcheck source=core/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
```

---

## Help Output Pattern

Keep help co-located with the binary, not in a separate file:

```bash
usage() {
    cat <<'EOF'
tool render <config.yml> [options]

  Builds segments, acts, and final video from intake index and plan.

Options:
  --dry-run         Print planned ffmpeg commands, skip encoding
  --only-act N      Render a single act (for previewing)
  --force           Re-render even if artifacts exist
EOF
    exit "${1:-0}"
}

# Parse flags before main logic
DRY_RUN=false
ONLY_ACT=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=true; shift ;;
        --only-act)   ONLY_ACT="$2"; shift 2 ;;
        --force)      FORCE=true; shift ;;
        --help|-h)    usage 0 ;;
        *)            echo "Unknown option: $1"; usage 1 ;;
    esac
done
```
