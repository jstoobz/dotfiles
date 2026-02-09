#!/bin/sh
# ============================================================================
# Step 08: Install pre-commit guardrails hook
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

install_guardrails() {
  info "Installing pre-commit guardrails hook"

  HOOK_SRC="${DOTFILES_ROOT}/hooks/pre-commit"
  HOOK_DST="${DOTFILES_ROOT}/.git/hooks/pre-commit"

  if [ -f "$HOOK_SRC" ]; then
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    success "Installed pre-commit hook"
  else
    info "No pre-commit hook source found, skipping"
  fi

  GUARDRAILS="${DOTFILES_ROOT}/.guardrails"
  GUARDRAILS_SAMPLE="${DOTFILES_ROOT}/.guardrails.sample"

  if [ ! -f "$GUARDRAILS" ] && [ -f "$GUARDRAILS_SAMPLE" ]; then
    cp "$GUARDRAILS_SAMPLE" "$GUARDRAILS"
    info "Created .guardrails from sample — edit it to add your blocked patterns"
  fi
}

install_guardrails
