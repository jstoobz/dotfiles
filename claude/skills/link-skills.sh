#!/bin/bash
#
# link-skills.sh — Symlink grouped skills into ~/.claude/skills/ (flat)
#
# Claude Code discovers skills one level deep: ~/.claude/skills/*/SKILL.md
# This script walks the grouped dotfiles structure and creates symlinks.
#
# Usage:
#   ./link-skills.sh          # link all skills
#   ./link-skills.sh --dry-run # preview without changes
#   ./link-skills.sh --clean   # remove dead symlinks first, then link

set -e

DOTFILES_SKILLS="$(cd "$(dirname "$0")" && pwd -P)"
CLAUDE_SKILLS="${HOME}/.claude/skills"
DRY_RUN=false
CLEAN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --clean) CLEAN=true ;;
  esac
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

info() { printf "  ${CYAN}info${RESET}  %s\n" "$1"; }
created() { printf "  ${GREEN}link${RESET}  %s -> %s\n" "$1" "$2"; }
skip() { printf "  ${YELLOW}skip${RESET}  %s (already exists)\n" "$1"; }
removed() { printf "  ${RED}clean${RESET} %s (dead symlink)\n" "$1"; }

# Ensure target directory exists
mkdir -p "$CLAUDE_SKILLS"

# Clean dead symlinks
if [ "$CLEAN" = true ]; then
  info "Cleaning dead symlinks..."
  find "$CLAUDE_SKILLS" -maxdepth 1 -type l ! -exec test -e {} \; -print | while read -r link; do
    if [ "$DRY_RUN" = true ]; then
      removed "$(basename "$link") [dry-run]"
    else
      rm "$link"
      removed "$(basename "$link")"
    fi
  done
fi

# Find all SKILL.md files and link their parent directories
linked=0
skipped=0

find "$DOTFILES_SKILLS" -name "SKILL.md" -type f | sort | while read -r skill_file; do
  skill_dir="$(dirname "$skill_file")"
  skill_name="$(basename "$skill_dir")"
  target="${CLAUDE_SKILLS}/${skill_name}"

  if [ -L "$target" ]; then
    # Symlink exists — check if it points to the right place
    current_target="$(readlink "$target")"
    if [ "$current_target" = "$skill_dir" ]; then
      skip "$skill_name"
      continue
    else
      # Points somewhere else — update it
      if [ "$DRY_RUN" = false ]; then
        rm "$target"
      fi
    fi
  elif [ -d "$target" ]; then
    # Real directory exists — skip (don't overwrite non-symlink dirs)
    printf "  ${RED}warn${RESET}  %s is a real directory, not a symlink. Skipping.\n" "$skill_name"
    continue
  fi

  if [ "$DRY_RUN" = true ]; then
    created "$skill_name" "$skill_dir [dry-run]"
  else
    ln -sf "$skill_dir" "$target"
    created "$skill_name" "$skill_dir"
  fi
done

# Also link top-level .md files (session-kit.md, etc.)
find "$DOTFILES_SKILLS" -maxdepth 2 -name "*.md" -not -name "SKILL.md" -not -name "CLAUDE.md" -type f | sort | while read -r md_file; do
  md_name="$(basename "$md_file")"
  target="${CLAUDE_SKILLS}/${md_name}"

  if [ -L "$target" ] || [ -f "$target" ]; then
    skip "$md_name"
  elif [ "$DRY_RUN" = true ]; then
    created "$md_name" "$md_file [dry-run]"
  else
    ln -sf "$md_file" "$target"
    created "$md_name" "$md_file"
  fi
done

echo ""
info "Done. Skills linked into ${CLAUDE_SKILLS}"
