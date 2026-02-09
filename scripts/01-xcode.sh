#!/bin/sh
# ============================================================================
# Step 01: Xcode Command Line Tools
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

install_xcode_cli_tools() {
  info "Checking for Xcode Command Line Tools..."

  [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ] && {
    success "Xcode Command Line Tools already installed"
    return
  }

  info "Installing the Xcode Command Line Tools:"

  CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  touch "${CLT_PLACEHOLDER}"
  CLT_PACKAGE=$(softwareupdate -l \
    | grep -B 1 "Command Line Tools" \
    | awk -F"*" '/^ *\*/ {print $2}' \
    | sed -e 's/^ *Label: //' -e 's/^ *//' \
    | sort -V \
    | tail -n1)

  softwareupdate -i "${CLT_PACKAGE}"

  [ -f "${CLT_PLACEHOLDER}" ] && rm -rf "${CLT_PLACEHOLDER}"

  success "Installed Xcode Command Line Tools"
}

install_xcode_cli_tools
