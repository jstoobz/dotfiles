#!/bin/bash
# ============================================================================
# Shared utility functions for bootstrap scripts
# ============================================================================

# Color Utilities
_RESET=$(tput sgr0)
_GREEN_BOLD=$(
  tput setaf 2
  tput bold
)

banner() {
  cat <<EOF
${_GREEN_BOLD}
       _     _              _
      (_)___| |_ ___   ___ | |__ ____
      | / __| __/ _ \ / _ \| '_ \_  /
      | \__ \ || (_) | (_) | |_) / /
     _/ |___/\__\___/ \___/|_.__/___|
    |__/
        By James Stephens (jstoobz)
${_RESET}
EOF
}

info() {
  # shellcheck disable=SC2059
  printf "\r  [ \033[00;34m..\033[0m ] $1\n"
}

user() {
  # shellcheck disable=SC2059
  printf "\r  [ \033[0;33m??\033[0m ] $1\n"
}

success() {
  # shellcheck disable=SC2059
  printf "\r\033[2K  [ \033[00;32mOK\033[0m ] $1\n"
}

fail() {
  # shellcheck disable=SC2059
  printf "\r\033[2K  [\033[0;31mFAIL\033[0m] $1\n"
}

warn() {
  # shellcheck disable=SC2059
  printf "\r\033[2K  [\033[0;33mWARN\033[0m] $1\n"
}

step() {
  # shellcheck disable=SC2059
  printf "\n==> \033[1m$1\033[0m\n"
}

clr_screen() {
  # shellcheck disable=SC2059
  printf "\033c"
}

padding() {
  # shellcheck disable=SC2059
  printf "\n"
}

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

# Shared backup destination for this install run. Each `./install` invocation
# gets one timestamped directory; individual steps sourcing utils.sh inherit it.
: "${BACKUP_DIR:=${HOME}/.dotfiles_backup/$(date +%Y%m%d-%H%M%S)}"
export BACKUP_DIR

# Move an existing path (file or symlink) into $BACKUP_DIR. No-op if missing.
archive_path() {
  local path="$1"

  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  mv "$path" "$BACKUP_DIR/"
  info "Archived: $path -> $BACKUP_DIR/"
}

symlink() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ]; then
    local existing
    existing="$(readlink "$dst")"
    if [ "$existing" = "$src" ]; then
      info "Already linked: $dst"
      return
    fi
  fi

  archive_path "$dst"
  ln -s "$src" "$dst"
  success "Linked: $dst -> $src"
}

# Counters for apply_default / apply_sudo_default. Callers reset these per
# section and print a summary at the end.
DEFAULTS_APPLIED=0
DEFAULTS_FAILED=0

# Run `defaults <args>`, tolerate failure, bump counters. Keeps the scripts
# idempotent and non-fatal on settings that vary by macOS version.
apply_default() {
  local description="$1"
  shift

  if defaults "$@" 2>/dev/null; then
    DEFAULTS_APPLIED=$((DEFAULTS_APPLIED + 1))
  else
    warn "skip: $description"
    DEFAULTS_FAILED=$((DEFAULTS_FAILED + 1))
  fi
}

apply_sudo_default() {
  local description="$1"
  shift

  if sudo defaults "$@" 2>/dev/null; then
    DEFAULTS_APPLIED=$((DEFAULTS_APPLIED + 1))
  else
    warn "skip: $description"
    DEFAULTS_FAILED=$((DEFAULTS_FAILED + 1))
  fi
}

# Set a nested plist value via PlistBuddy. Tries Set first (value exists),
# falls back to Add (value does not exist). One call per setting instead of
# the five-line try/Add pattern used in the source scripts.
#   plist_set <plist> <key-path> <type> <value>
#   type: bool | integer | string | real | date | data | array | dict
plist_set() {
  local plist="$1"
  local keypath="$2"
  local type="$3"
  local value="$4"

  if /usr/libexec/PlistBuddy -c "Set ${keypath} ${value}" "$plist" 2>/dev/null; then
    return 0
  fi
  /usr/libexec/PlistBuddy -c "Add ${keypath} ${type} ${value}" "$plist" 2>/dev/null
}
