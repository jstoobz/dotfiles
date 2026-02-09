#!/bin/sh
# ============================================================================
# Step 02: Homebrew install + brew bundle
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

install_homebrew() {
  info "Checking for Homebrew..."

  if command_exists brew; then
    info "Homebrew already installed"
  else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success "Installed Homebrew"
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"

  brew update
  brew upgrade
  success "Updated Homebrew"

  info "Installing formulae and casks from Brewfile"
  brew bundle --file="${DOTFILES_ROOT}/Brewfile"
  success "Installed brew bundle"
}

install_homebrew
