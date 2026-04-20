#!/usr/bin/env bash
# ============================================================================
# macOS Finder view settings — Desktop, Icon, List, Column, Gallery
#
# Uses PlistBuddy rather than `defaults` because `defaults write` can't reach
# into nested dicts like :StandardViewSettings:IconViewSettings:iconSize.
# plist_set (lib/utils.sh) wraps the Set-else-Add pattern for each key.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/utils.sh
. "${SCRIPT_DIR}/../../lib/utils.sh"

PLIST="${HOME}/Library/Preferences/com.apple.finder.plist"

main() {
  step "Finder view settings"

  # Desktop icon view
  info "Desktop view"
  plist_set "$PLIST" ":DesktopViewSettings:IconViewSettings:showItemInfo" bool true
  plist_set "$PLIST" ":DesktopViewSettings:IconViewSettings:showIconPreview" bool true
  plist_set "$PLIST" ":DesktopViewSettings:IconViewSettings:iconSize" integer 64
  plist_set "$PLIST" ":DesktopViewSettings:IconViewSettings:gridSpacing" integer 100
  plist_set "$PLIST" ":DesktopViewSettings:IconViewSettings:arrangeBy" string kind

  # Default icon view (new windows)
  info "Icon view"
  plist_set "$PLIST" ":StandardViewSettings:IconViewSettings:iconSize" integer 64
  plist_set "$PLIST" ":StandardViewSettings:IconViewSettings:gridSpacing" integer 100
  plist_set "$PLIST" ":StandardViewSettings:IconViewSettings:showItemInfo" bool true
  plist_set "$PLIST" ":StandardViewSettings:IconViewSettings:showIconPreview" bool true
  plist_set "$PLIST" ":StandardViewSettings:IconViewSettings:arrangeBy" string kind

  # List view
  info "List view"
  defaults write com.apple.finder CalculateAllSizes -bool true 2>/dev/null || warn "List: CalculateAllSizes"
  plist_set "$PLIST" ":StandardViewSettings:ListViewSettings:textSize" integer 13
  plist_set "$PLIST" ":StandardViewSettings:ListViewSettings:iconSize" integer 16
  plist_set "$PLIST" ":StandardViewSettings:ListViewSettings:showIconPreview" bool true
  plist_set "$PLIST" ":StandardViewSettings:ListViewSettings:sortColumn" string name
  plist_set "$PLIST" ":StandardViewSettings:ListViewSettings:useRelativeDates" bool true

  # Column view (nested under ExtendedListViewSettingsV2 on Sonoma+)
  info "Column view"
  plist_set "$PLIST" ":StandardViewSettings:ExtendedListViewSettingsV2:textSize" integer 13
  plist_set "$PLIST" ":StandardViewSettings:ExtendedListViewSettingsV2:iconSize" integer 16
  plist_set "$PLIST" ":StandardViewSettings:ExtendedListViewSettingsV2:showIconPreview" bool true
  plist_set "$PLIST" ":StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes" bool true

  # Gallery view
  info "Gallery view"
  plist_set "$PLIST" ":StandardViewSettings:GalleryViewSettings:showPreviewPane" bool true

  # Default window view — Nlsv=List, icnv=Icon, clmv=Column, glyv=Gallery
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

  # cfprefsd owns the cached plist; restart it before Finder so our writes
  # aren't overwritten by the stale cache on next sync.
  killall cfprefsd 2>/dev/null || true
  killall Finder 2>/dev/null || true

  success "Finder view settings applied"
}

main "$@"
