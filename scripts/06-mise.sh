#!/bin/sh
# ============================================================================
# Step 06: mise version manager + language runtimes
# Reads from ~/.tool-versions (symlinked from dotfiles)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

configure_mise() {
  info "Configuring mise"

  eval "$(mise activate sh)"

  TOOL_VERSIONS="${DOTFILES_ROOT}/config/mise/.tool-versions"

  if [ ! -f "$TOOL_VERSIONS" ]; then
    fail "No .tool-versions found at ${TOOL_VERSIONS}"
    return 1
  fi

  symlink "$TOOL_VERSIONS" "${HOME}/.tool-versions"

  info "Installing runtimes from .tool-versions"
  mise install
  success "Installed runtimes"

  if command_exists mix; then
    info "Installing hex, rebar, and phx_new"
    mix local.hex --if-missing --force
    mix local.rebar --if-missing --force
    mix archive.install hex phx_new --force
    success "Installed Elixir tooling"
  else
    info "Elixir not in .tool-versions, skipping hex/rebar/phx_new"
  fi

  success "Configured mise and language runtimes"
}

configure_mise
