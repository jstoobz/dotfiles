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
