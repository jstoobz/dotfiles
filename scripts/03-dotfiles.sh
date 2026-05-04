#!/bin/sh
# ============================================================================
# Step 03: Symlink dotfiles configs into home directory
# Backs up existing real files before overwriting.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

link_dotfiles() {
  info "Setting up config symlinks"

  # Ensure XDG directories exist
  mkdir -p "${HOME}/.config/zsh"
  mkdir -p "${HOME}/.config/nvim"
  mkdir -p "${HOME}/.config/mise"

  # Symlink configs
  symlink "${DOTFILES_ROOT}/config/zsh/.zshrc" "${HOME}/.zshrc"
  symlink "${DOTFILES_ROOT}/config/zsh/aliases.zsh" "${HOME}/.config/zsh/aliases.zsh"
  symlink "${DOTFILES_ROOT}/config/zsh/functions.zsh" "${HOME}/.config/zsh/functions.zsh"
  symlink "${DOTFILES_ROOT}/config/git/.gitignore_global" "${HOME}/.gitignore_global"
  symlink "${DOTFILES_ROOT}/config/editor/.editorconfig" "${HOME}/.editorconfig"
  symlink "${DOTFILES_ROOT}/config/misc/.hushlogin" "${HOME}/.hushlogin"
  symlink "${DOTFILES_ROOT}/config/iex/.iex.exs" "${HOME}/.iex.exs"
  symlink "${DOTFILES_ROOT}/config/mise/config.toml" "${HOME}/.config/mise/config.toml"
  symlink "${DOTFILES_ROOT}/config/starship/starship.toml" "${HOME}/.config/starship.toml"
  mkdir -p "${HOME}/.config/ghostty"
  symlink "${DOTFILES_ROOT}/config/ghostty/config" "${HOME}/.config/ghostty/config"
  symlink "${DOTFILES_ROOT}/config/nvim/init.lua" "${HOME}/.config/nvim/init.lua"
  symlink "${DOTFILES_ROOT}/config/tmux/.tmux.conf" "${HOME}/.tmux.conf"
  mkdir -p "${HOME}/.config/lazygit"
  symlink "${DOTFILES_ROOT}/config/lazygit/config.yml" "${HOME}/.config/lazygit/config.yml"
  mkdir -p "${HOME}/.config/aerospace"
  symlink "${DOTFILES_ROOT}/config/aerospace/aerospace.toml" "${HOME}/.config/aerospace/aerospace.toml"
  mkdir -p "${HOME}/.config/pgcli"
  symlink "${DOTFILES_ROOT}/config/pgcli/config" "${HOME}/.config/pgcli/config"
  mkdir -p "${HOME}/.config/bat"
  symlink "${DOTFILES_ROOT}/config/bat/config" "${HOME}/.config/bat/config"
  mkdir -p "${HOME}/.config/ripgrep"
  symlink "${DOTFILES_ROOT}/config/ripgrep/.ripgreprc" "${HOME}/.config/ripgrep/.ripgreprc"
  mkdir -p "${HOME}/.ssh"
  symlink "${DOTFILES_ROOT}/config/ssh/config" "${HOME}/.ssh/config"
  mkdir -p "${HOME}/.config/direnv"
  symlink "${DOTFILES_ROOT}/config/direnv/direnv.toml" "${HOME}/.config/direnv/direnv.toml"

  success "Symlinked all config files"
}

link_dotfiles
