#!/usr/bin/env bash
# ============================================================================
# Step 11: macOS hardening
#
# Dispatches to three sub-scripts under scripts/macos/:
#   defaults.sh   — UI/UX, input, Finder, Dock, crash reporter
#   finder.sh     — PlistBuddy view settings (requires cfprefsd restart)
#   security.sh   — firewall, privacy, Siri/ads/diagnostics opt-outs
#
# Requires sudo. The install runner prompts when `--only macos` or a full
# install is invoked (see SUDO_STEPS gate).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/utils.sh
. "${SCRIPT_DIR}/../lib/utils.sh"

MACOS_DIR="${SCRIPT_DIR}/macos"
STATE_DIR="${HOME}/.cache/dotfiles"
STATE_MARK="${STATE_DIR}/macos-hardened"

run() {
  local script="$1"
  if [ -x "$script" ]; then
    bash -e "$script"
  else
    fail "Not executable: $script"
    return 1
  fi
}

run "${MACOS_DIR}/defaults.sh"
run "${MACOS_DIR}/finder.sh"
run "${MACOS_DIR}/security.sh"

# Sentinel for `./install --verify` to detect "step 11 never ran on this box".
mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" >"$STATE_MARK"

echo ""
success "macOS hardening complete — some settings require logout/restart"
info "Sentinel: $STATE_MARK"
