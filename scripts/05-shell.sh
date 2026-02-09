#!/bin/sh
# ============================================================================
# Step 05: Zsh setup (no Oh My Zsh)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

configure_shell() {
  info "Configuring Zsh as default shell"

  ZSH_PATH="$(which zsh)"

  # Add Homebrew zsh to /etc/shells if missing
  if ! grep -q "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    info "Added $ZSH_PATH to /etc/shells"
  fi

  # Set as default shell if not already
  if [ "$SHELL" != "$ZSH_PATH" ]; then
    chsh -s "$ZSH_PATH"
    success "Set default shell to $ZSH_PATH"
  else
    info "Zsh is already the default shell"
  fi

  success "Shell configured"
}

configure_shell
