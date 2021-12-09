#!/bin/sh

set -e

DOTFILES_ROOT=$(pwd -P)

GITHUB_REPOSITORY="jstoobz/dotfiles"
DOTFILES_TARBALL_URL="https://github.com/$GITHUB_REPOSITORY/tarball/main"
DOTFILES_HOME_DIR="${HOME}/.dotfiles"

OSX_VERS=$(sw_vers -productVersion)
SW_BUILD=$(sw_vers -buildVersion)

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
  printf "\r\033[2K  [\033[0;31mFAIL\033[0m] $1\n\n"
  # exit
}

clr_screen() {
  # shellcheck disable=SC2059
  printf "\033c"
}

padding() {
  # shellcheck disable=SC2059
  printf "\n"
}

ask_for_sudo() {
  # Ask for the administrator password upfront
  sudo -v

  # Update existing `sudo` time stamp until the script has finished
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null &
}

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

extract() {
  archive="$1"
  outputDir="$2"

  command_exists "tar" &&
    tar -zxf "$archive" --strip-components 1 -C "$outputDir"
}

download() {
  url="$1"
  output="$2"

  info "url: ${url}"

  if command_exists curl; then
    curl -LsSo "$output" "$url" >/dev/null 2>&1
    return $?
  elif command_exists wget; then
    wget -qO "$output" "$url" >/dev/null 2>&1
    return $?
  fi

  return 1
}

symlink() {
  if [ -e "${HOME}/$1" ]; then
    info "Already exists: $file"
  else
    ln -sf "${DOTFILES_HOME_DIR}/$1" "${HOME}/$1"
    info "Create the symbolic link: $1"
  fi
}

create_symlinks() {
  symlink ".gitconfig"
  symlink ".gitignore"
  symlink ".editorconfig"
  symlink ".hushlogin"
  symlink ".zshrc"
}

install_xcode_cli_tools() {
  info "Checking for Xcode Command Line Tools..."

  if [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ]; then
    success "Xcode Command Line Tools already installed"
    return
  fi

  info "Installing the Xcode Command Line Tools:"

  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  touch "${CLT_PLACEHOLDER}"
  CLT_PACKAGE=$(softwareupdate -l |
    grep -B 1 "Command Line Tools" |
    awk -F"*" '/^ *\*/ {print $2}' |
    sed -e 's/^ *Label: //' -e 's/^ *//' |
    sort -V |
    tail -n1)

  softwareupdate -i "${CLT_PACKAGE}"

  info "Removing temp file..."
  [ -f "${CLT_PLACEHOLDER}" ] && rm -rf "${CLT_PLACEHOLDER}"

  success "Installed Xcode"
}

install_homebrew() {
  info "Checking for Homebrew..."

  if command_exists brew; then
    info "Homebrew already installed."
  else
    info "Installing Homebrew..."
    printf "\n" |
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    success "Installed Homebrew"
  fi

  brew update
  brew upgrade
  success "Updated Homebrew"
}

download_dotfiles() {
  info "Downloading and extracting archive..."
  tmpFile=""
  tmpFile="$(mktemp /tmp/XXXXX)"
  download "$DOTFILES_TARBALL_URL" "$tmpFile"

  # Add in verification to move a current .dotfiles directory
  # to a backup and install fresh
  [ ! -d "${DOTFILES_HOME_DIR}" ] && mkdir "$DOTFILES_HOME_DIR"

  info "Extracting archive"
  extract "$tmpFile" "$DOTFILES_HOME_DIR"
  success "Extracted archive"
  cd "$DOTFILES_HOME_DIR"
  info "Current working directory: $(pwd -P)"
}

install_brew_formulae_and_casks() {
  info "Installing brew formulae and casks"
  ./brew.sh
  success "Installed brew formulae and casks"
}

main() {
  ask_for_sudo "$@"
  clr_screen "$@"
  padding "$@"
  banner "$@"
  info "MacOS Version: ${OSX_VERS}"
  info "MacOS SW Build: ${SW_BUILD}"
  create_symlinks "$@"
  install_xcode_cli_tools "$@"
  install_homebrew "$@"
  download_dotfiles "$@"
  install_brew_formulae_and_casks "$@"
}

main "$@"