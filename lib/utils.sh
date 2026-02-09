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

symlink() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ]; then
    info "Already linked: $dst"
  elif [ -e "$dst" ]; then
    info "Exists (not a symlink): $dst — skipping"
  else
    ln -sf "$src" "$dst"
    success "Linked: $dst -> $src"
  fi
}

backup_if_exists() {
  local file="$1"
  local backup_dir="$2"

  if [ -e "$file" ] && [ ! -L "$file" ]; then
    mkdir -p "$backup_dir"
    cp -a "$file" "$backup_dir/"
    info "Backed up: $file -> $backup_dir/"
  fi
}
