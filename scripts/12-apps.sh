#!/usr/bin/env bash
# ============================================================================
# Step 12: Third-party app preferences
#
# Applies preferences for apps that store config in macOS defaults (plist)
# rather than config files. Each app has its own sub-script under scripts/apps/.
#
# Does not require sudo.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

APPS_DIR="${SCRIPT_DIR}/apps"

run_app() {
  local script="$1"
  if [ -x "$script" ]; then
    bash -e "$script"
  else
    fail "Not executable: $script"
  fi
}

info "Applying third-party app preferences"

run_app "${APPS_DIR}/rectangle.sh"

success "App preferences applied"
