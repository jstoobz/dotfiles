#!/usr/bin/env bash
# ============================================================================
# macOS security hardening — firewall, FileVault/SIP/Gatekeeper checks,
# privacy, lock screen, telemetry opt-outs.
#
# Destructive operations (FileVault enable, SIP disable) are deliberately
# not automated — they require user interaction and recovery-key handling.
# This script only *checks* FileVault/SIP and warns if they're off.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/utils.sh
. "${SCRIPT_DIR}/../../lib/utils.sh"

DEFAULTS_APPLIED=0
DEFAULTS_FAILED=0

FW=/usr/libexec/ApplicationFirewall/socketfilterfw

main() {
  step "macOS security hardening"

  # ==========================================================================
  step "Firewall"
  # ==========================================================================

  info "macOS firewall only blocks inbound. For outbound, see Lulu (cask)."

  fw_set() {
    local description="$1"
    shift
    if sudo "$FW" "$@" >/dev/null 2>&1; then
      success "$description"
    else
      warn "$description: could not set"
    fi
  }

  fw_set "Firewall enabled" --setglobalstate on
  fw_set "Stealth mode on" --setstealthmode on
  fw_set "Firewall logging on" --setloggingmode on
  fw_set "Block-all off (essential services allowed)" --setblockall off
  fw_set "Signed apps allowed inbound" --setallowsigned on
  fw_set "Signed downloads allowed inbound" --setallowsignedapp on

  # ==========================================================================
  step "FileVault"
  # ==========================================================================

  local fv_status
  fv_status=$(fdesetup status 2>/dev/null || echo "Unknown")
  if echo "$fv_status" | grep -q "On"; then
    success "FileVault enabled"
  elif echo "$fv_status" | grep -q "Off"; then
    warn "FileVault is OFF — enable via System Settings > Privacy & Security > FileVault"
  else
    info "FileVault status: $fv_status"
  fi

  # ==========================================================================
  step "System Integrity Protection"
  # ==========================================================================

  local sip_status
  sip_status=$(csrutil status 2>/dev/null || echo "Unknown")
  if echo "$sip_status" | grep -q "enabled"; then
    success "SIP enabled"
  else
    warn "SIP: $sip_status"
  fi

  # ==========================================================================
  step "Gatekeeper"
  # ==========================================================================

  local gk_status
  gk_status=$(spctl --status 2>/dev/null || echo "Unknown")
  if echo "$gk_status" | grep -q "enabled"; then
    success "Gatekeeper enabled"
  else
    # --global-enable is the Sonoma+ flag; --master-enable is deprecated.
    # Try modern first, fall back to legacy.
    if sudo spctl --global-enable >/dev/null 2>&1; then
      success "Gatekeeper enabled (--global-enable)"
    elif sudo spctl --master-enable >/dev/null 2>&1; then
      success "Gatekeeper enabled (--master-enable, legacy)"
    else
      warn "Could not enable Gatekeeper"
    fi
  fi

  # ==========================================================================
  step "Network & sharing"
  # ==========================================================================

  if sudo systemsetup -setremoteappleevents off >/dev/null 2>&1; then
    success "Remote Apple events disabled"
  else
    warn "Remote Apple events: could not disable"
  fi
  if sudo systemsetup -setwakeonnetworkaccess off >/dev/null 2>&1; then
    success "Wake-on-network disabled"
  else
    warn "Wake-on-network: could not disable"
  fi
  apply_default "Bluetooth sharing off" -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false
  apply_sudo_default "Infrared remote off" write /Library/Preferences/com.apple.driver.AppleIRController DeviceEnabled -bool false

  # ==========================================================================
  step "Siri, ads, diagnostics"
  # ==========================================================================

  apply_default "Siri off" write com.apple.assistant.support "Assistant Enabled" -bool false
  apply_default "Siri menu hidden" write com.apple.Siri StatusMenuVisible -bool false
  apply_default "Siri declined" write com.apple.assistant.support UserHasDeclinedEnable -bool true
  apply_default "Siri data sharing opt-out" write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2
  apply_default "Siri search-query data opt-out" write com.apple.assistant.support "Search Queries Data Sharing Status" -int 2
  apply_default "Dictation data sharing opt-out" write com.apple.assistant.backedup "Dictation Data Sharing Opt-In Status" -int 2
  apply_default "Personalized ads off" write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
  apply_default "Ad identifier off" write com.apple.AdLib allowIdentifierForAdvertising -bool false
  apply_default "Feedback Assistant auto-gather off" write com.apple.appleseed.FeedbackAssistant Autogather -bool false

  # ==========================================================================
  step "Lock screen & hibernation"
  # ==========================================================================

  apply_default "Require password after sleep" write com.apple.screensaver askForPassword -int 1
  apply_default "No password grace period" write com.apple.screensaver askForPasswordDelay -int 0
  apply_sudo_default "Secure virtual memory" write /Library/Preferences/com.apple.virtualMemory DisableEncryptedSwap -bool false

  # Laptop-only: destroy FileVault key on standby so a stolen sleeping laptop
  # can't be woken into an unlocked session. hibernatemode 25 forces full
  # hibernation (RAM → disk, then power-off) before sleep completes.
  if [[ "$(sysctl -n hw.model 2>/dev/null)" == *Book* ]]; then
    if sudo pmset -a destroyfvkeyonstandby 1 2>/dev/null; then
      success "FileVault key destroyed on standby"
    else
      warn "Could not set destroyfvkeyonstandby"
    fi
    if sudo pmset -a hibernatemode 25 2>/dev/null; then
      success "Hibernation mode 25 (full)"
    else
      warn "Could not set hibernatemode"
    fi
  fi

  echo ""
  success "Security hardening: ${DEFAULTS_APPLIED} settings applied, ${DEFAULTS_FAILED} skipped"
  info "For outbound firewall: Lulu ships in this Brewfile (cask 'lulu')"
}

main "$@"
