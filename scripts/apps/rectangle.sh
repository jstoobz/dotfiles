#!/usr/bin/env bash
# Rectangle preferences
# Docs: https://github.com/rxhanson/Rectangle
#
# Rectangle stores config in macOS defaults, not a file — so this script
# applies preferences idempotently. Safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../../lib/utils.sh"

DOMAIN="com.knollsoft.Rectangle"

apply_rectangle() {
  info "Applying Rectangle preferences"

  # Use ctrl+opt shortcuts (alt set) instead of cmd+opt (default set).
  # Avoids conflicts with common app shortcuts like cmd+opt+left/right.
  apply_default "Rectangle: alternate shortcuts" write "${DOMAIN}" alternateDefaultShortcuts -bool true

  # Allow overriding any shortcut in preferences.
  apply_default "Rectangle: allow any shortcut" write "${DOMAIN}" allowAnyShortcut -bool true

  # Managed via Homebrew — no in-app update prompts needed.
  apply_default "Rectangle: disable auto-update checks" write "${DOMAIN}" SUEnableAutomaticChecks -bool false

  # Repeating a snap command cycles: half → third → two-thirds → half.
  # Set to 2 to cycle through different sizes instead.
  apply_default "Rectangle: subsequent execution mode" write "${DOMAIN}" subsequentExecutionMode -int 1

  success "Rectangle preferences applied"
  info "Restart Rectangle to pick up any changes: killall Rectangle && open -a Rectangle"
}

apply_rectangle
