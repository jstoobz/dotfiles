#!/bin/sh
# ============================================================================
# Step 09: Link Claude Code config and skills
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

link_claude_config() {
  info "Linking Claude Code config from dotfiles"

  CLAUDE_DIR="${HOME}/.claude"
  CLAUDE_SRC="${DOTFILES_ROOT}/claude"

  [ ! -d "$CLAUDE_DIR" ] && mkdir -p "$CLAUDE_DIR"

  if [ -f "${CLAUDE_SRC}/settings.json" ]; then
    symlink "${CLAUDE_SRC}/settings.json" "${CLAUDE_DIR}/settings.json"
  else
    info "No Claude settings.json found, skipping"
  fi

  if [ -f "${CLAUDE_SRC}/CLAUDE.md" ]; then
    symlink "${CLAUDE_SRC}/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
  else
    info "No Claude CLAUDE.md found, skipping"
  fi
}

link_claude_skills() {
  info "Linking Claude Code skills from dotfiles"

  SKILLS_LINK_SCRIPT="${DOTFILES_ROOT}/claude/skills/link-skills.sh"

  if [ -x "$SKILLS_LINK_SCRIPT" ]; then
    "$SKILLS_LINK_SCRIPT" --clean
    success "Linked Claude Code skills"
  else
    info "No Claude skills link script found, skipping"
  fi
}

link_claude_config
link_claude_skills
