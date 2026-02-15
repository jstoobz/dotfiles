#!/bin/sh
# ============================================================================
# Step 10: VSCodium editor setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

if ! command_exists codium; then
  info "codium CLI not found — skipping editor setup"
  exit 0
fi

VSCODE_SRC="${DOTFILES_ROOT}/vscode"
VSCODE_USER="${HOME}/Library/Application Support/VSCodium/User"

# ── Symlink config files ──────────────────────────────────────────────────

mkdir -p "${VSCODE_USER}"
mkdir -p "${VSCODE_USER}/snippets"

symlink "${VSCODE_SRC}/settings.json"          "${VSCODE_USER}/settings.json"
symlink "${VSCODE_SRC}/keybindings.json"        "${VSCODE_USER}/keybindings.json"
symlink "${VSCODE_SRC}/snippets/elixir.json"    "${VSCODE_USER}/snippets/elixir.json"

# ── Install extensions ────────────────────────────────────────────────────

EXTENSIONS_FILE="${VSCODE_SRC}/.extensions"

if [ ! -f "$EXTENSIONS_FILE" ]; then
  info "No .extensions file found — skipping extension install"
  exit 0
fi

INSTALLED=$(codium --list-extensions 2>/dev/null)

while IFS= read -r ext || [ -n "$ext" ]; do
  ext=$(echo "$ext" | sed 's/#.*//' | xargs)
  [ -z "$ext" ] && continue

  if echo "$INSTALLED" | grep -qi "^${ext}$"; then
    info "Extension already installed: $ext"
  else
    info "Installing extension: $ext"
    codium --install-extension "$ext" --force >/dev/null 2>&1 || fail "Failed to install: $ext"
  fi
done < "$EXTENSIONS_FILE"

success "VSCodium editor setup complete"
