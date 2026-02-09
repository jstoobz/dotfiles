#!/bin/sh
# ============================================================================
# Step 03: Symlink dotfiles configs into home directory
# Backs up existing real files before overwriting.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

BACKUP_DIR="${HOME}/.dotfiles_backup/$(date +%Y%m%d-%H%M%S)"

link_dotfiles() {
  info "Setting up config symlinks"

  # Back up existing real files (skip if already symlinks)
  backup_if_exists "${HOME}/.zshrc" "$BACKUP_DIR"
  backup_if_exists "${HOME}/.gitignore_global" "$BACKUP_DIR"
  backup_if_exists "${HOME}/.editorconfig" "$BACKUP_DIR"
  backup_if_exists "${HOME}/.hushlogin" "$BACKUP_DIR"
  backup_if_exists "${HOME}/.iex.exs" "$BACKUP_DIR"

  # Ensure XDG directories exist
  mkdir -p "${HOME}/.config/zsh"

  # Symlink configs
  symlink "${DOTFILES_ROOT}/config/zsh/.zshrc" "${HOME}/.zshrc"
  symlink "${DOTFILES_ROOT}/config/zsh/aliases.zsh" "${HOME}/.config/zsh/aliases.zsh"
  symlink "${DOTFILES_ROOT}/config/zsh/functions.zsh" "${HOME}/.config/zsh/functions.zsh"
  symlink "${DOTFILES_ROOT}/config/git/.gitignore_global" "${HOME}/.gitignore_global"
  symlink "${DOTFILES_ROOT}/config/editor/.editorconfig" "${HOME}/.editorconfig"
  symlink "${DOTFILES_ROOT}/config/misc/.hushlogin" "${HOME}/.hushlogin"
  symlink "${DOTFILES_ROOT}/config/iex/.iex.exs" "${HOME}/.iex.exs"
  symlink "${DOTFILES_ROOT}/config/mise/.tool-versions" "${HOME}/.tool-versions"

  success "Symlinked all config files"
}

link_dotfiles
