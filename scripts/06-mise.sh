#!/bin/sh
# ============================================================================
# Step 06: mise version manager + language runtimes
# Reads from ~/.config/mise/config.toml (symlinked from dotfiles by step 03)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

configure_mise() {
  info "Configuring mise"

  eval "$(mise activate sh)"

  MISE_CONFIG="${DOTFILES_ROOT}/config/mise/config.toml"

  if [ ! -f "$MISE_CONFIG" ]; then
    fail "No config.toml found at ${MISE_CONFIG}"
    return 1
  fi

  mkdir -p "${HOME}/.config/mise"
  symlink "$MISE_CONFIG" "${HOME}/.config/mise/config.toml"

  info "Installing runtimes from config.toml"
  mise install
  success "Installed runtimes"

  if command_exists mix; then
    info "Installing hex, rebar, and phx_new"
    mix local.hex --if-missing --force
    mix local.rebar --if-missing --force
    mix archive.install hex phx_new --force
    success "Installed Elixir tooling"
  else
    info "Elixir not declared in config.toml, skipping hex/rebar/phx_new"
  fi

  success "Configured mise and language runtimes"
}

configure_mise
