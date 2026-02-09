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

  command_exists "tar" \
    && tar -zxf "$archive" --strip-components 1 -C "$outputDir"
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
    info "Already exists: $1"
  else
    ln -sf "${DOTFILES_HOME_DIR}/$1" "${HOME}/$1"
    success "Created the symlink for: $1"
  fi
}

generate_gitconfig() {
  info "Generating .gitconfig from template"

  TEMPLATE="${DOTFILES_HOME_DIR}/.gitconfig.template"
  OUTPUT="${DOTFILES_HOME_DIR}/.gitconfig"

  if [ ! -f "$TEMPLATE" ]; then
    fail ".gitconfig.template not found"
    return 1
  fi

  if [ -f "$OUTPUT" ]; then
    info ".gitconfig already exists, skipping generation"
    return
  fi

  user "Enter your Git user name:"
  read -r git_name
  user "Enter your Git email:"
  read -r git_email

  sed -e "s|__GIT_USER_NAME__|${git_name}|g" \
    -e "s|__GIT_USER_EMAIL__|${git_email}|g" \
    -e "s|__HOME_DIR__|${HOME}|g" \
    "$TEMPLATE" >"$OUTPUT"

  success "Generated .gitconfig for ${git_name} <${git_email}>"
}

create_symlinks() {
  info "Settings up symlinks for config files"

  symlink ".gitconfig"
  symlink ".gitignore"
  symlink ".editorconfig"
  symlink ".hushlogin"
  symlink ".zshrc"

  success "Symlinked all config files"
}

install_xcode_cli_tools() {
  info "Checking for Xcode Command Line Tools..."

  [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ] && {
    success "Xcode Command Line Tools already installed"
    return
  }

  info "Installing the Xcode Command Line Tools:"

  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  touch "${CLT_PLACEHOLDER}"
  CLT_PACKAGE=$(softwareupdate -l \
    | grep -B 1 "Command Line Tools" \
    | awk -F"*" '/^ *\*/ {print $2}' \
    | sed -e 's/^ *Label: //' -e 's/^ *//' \
    | sort -V \
    | tail -n1)

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
    printf "\n" \
      | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    success "Installed Homebrew"
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"

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

install_oh_my_zsh() {
  [ -d "${HOME}/.oh-my-zsh" ] && {
    info "Oh my zsh already installed."
    return
  }

  info "Installing oh my zsh"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
  success "Installed oh my zsh"
}

configure_asdf() {
  info "Configuring asdf and relevant plugins"

  # asdf scripts needed during nodejs install for reshim
  # also avoiding reloading shell for .zshrc and exiting script
  . $(brew --prefix asdf)/libexec/asdf.sh

  info "Installing asdf plugin for erlang, elixir, nodejs, and yarn"
  [ ! -d "$ASDF_DIR/plugins/erlang" ] && asdf plugin add erlang
  [ ! -d "$ASDF_DIR/plugins/elixir" ] && asdf plugin add elixir
  [ ! -d "$ASDF_DIR/plugins/nodejs" ] && asdf plugin add nodejs
  [ ! -d "$ASDF_DIR/plugins/yarn" ] && asdf plugin add yarn
  success "asdf plugins added for erlang, elixir, nodejs, and yarn"

  info "Installing latest versions of erlang, elixir, nodejs, and yarn"
  asdf install erlang latest
  asdf install elixir latest
  asdf install nodejs latest
  asdf install yarn latest
  success "Installed latest versions of erlang, elixir, nodejs, and yarn"

  info "Setting asdf global versions for erlang, elixir, nodejs, and yarn"
  asdf global erlang "$(asdf latest erlang)"
  asdf global elixir "$(asdf latest elixir)"
  asdf global nodejs "$(asdf latest nodejs)"
  asdf global yarn "$(asdf latest yarn)"
  success "Set asdf global versions for erlang, elixir, nodejs, and yarn"

  info "Importing Node.js release team's OpenPGP keys to the keyring"
  bash -c "${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring"
  success "Imported Node.js release team's OpenPGP keys to the keyring"

  info "Installing hex"
  mix local.hex --if-missing --force
  success "Installed hex"

  info "Installing rebar"
  mix local.rebar --if-missing --force
  success "Installed rebar"

  info "Installing mix archive for hex phx_new"
  mix archive.install hex phx_new --force
  success "Installed mix archive for hex phx_new"

  success "Configured asdf and relevant plugins"
}

configure_postgres() {
  info "Starting postgresql and creating default postgres user"
  brew services start postgresql

  # Wait until postgresql is listening on port 5432
  while ! lsof -i :5432 >/dev/null 2>&1; do sleep 1; done

  createuser -s postgres
  success "Started postgresql and created default postgres user"
}

install_guardrails_hook() {
  info "Installing pre-commit guardrails hook"

  HOOK_SRC="${DOTFILES_HOME_DIR}/hooks/pre-commit"
  HOOK_DST="${DOTFILES_HOME_DIR}/.git/hooks/pre-commit"

  if [ -f "$HOOK_SRC" ]; then
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    success "Installed pre-commit hook"
  else
    info "No pre-commit hook source found, skipping"
  fi

  GUARDRAILS="${DOTFILES_HOME_DIR}/.guardrails"
  GUARDRAILS_SAMPLE="${DOTFILES_HOME_DIR}/.guardrails.sample"

  if [ ! -f "$GUARDRAILS" ] && [ -f "$GUARDRAILS_SAMPLE" ]; then
    cp "$GUARDRAILS_SAMPLE" "$GUARDRAILS"
    info "Created .guardrails from sample — edit it to add your blocked patterns"
  fi
}

link_claude_config() {
  info "Linking Claude Code config from dotfiles"

  CLAUDE_DIR="${HOME}/.claude"
  CLAUDE_SRC="${DOTFILES_HOME_DIR}/claude"

  [ ! -d "$CLAUDE_DIR" ] && mkdir -p "$CLAUDE_DIR"

  if [ -f "${CLAUDE_SRC}/settings.json" ]; then
    ln -sf "${CLAUDE_SRC}/settings.json" "${CLAUDE_DIR}/settings.json"
    success "Linked Claude Code settings.json"
  else
    info "No Claude settings.json found in dotfiles, skipping"
  fi

  if [ -f "${CLAUDE_SRC}/CLAUDE.md" ]; then
    ln -sf "${CLAUDE_SRC}/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
    success "Linked Claude Code CLAUDE.md"
  else
    info "No Claude CLAUDE.md found in dotfiles, skipping"
  fi
}

link_claude_skills() {
  info "Linking Claude Code skills from dotfiles"

  SKILLS_LINK_SCRIPT="${DOTFILES_HOME_DIR}/claude/skills/link-skills.sh"

  if [ -x "$SKILLS_LINK_SCRIPT" ]; then
    "$SKILLS_LINK_SCRIPT" --clean
    success "Linked Claude Code skills"
  else
    info "No Claude skills link script found, skipping"
  fi
}

main() {
  ask_for_sudo "$@"
  clr_screen "$@"
  padding "$@"
  banner "$@"
  info "MacOS Version: ${OSX_VERS}"
  info "MacOS SW Build: ${SW_BUILD}"
  generate_gitconfig "$@"
  create_symlinks "$@"
  install_xcode_cli_tools "$@"
  install_homebrew "$@"
  download_dotfiles "$@"
  install_brew_formulae_and_casks "$@"
  install_oh_my_zsh "$@"
  configure_asdf "$@"
  configure_postgres "$@"
  link_claude_config "$@"
  link_claude_skills "$@"
  install_guardrails_hook "$@"
  success "Completed dotfile installation"
}

main "$@"
