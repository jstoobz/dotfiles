#!/bin/sh
# ============================================================================
# Dotfiles Bootstrap — curl-friendly entrypoint
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/jstoobz/dotfiles/main/bootstrap.sh | bash
#   curl -sL https://raw.githubusercontent.com/jstoobz/dotfiles/main/bootstrap.sh | bash -s -- --dry-run
# ============================================================================

set -e

GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

printf "${GREEN}${BOLD}"
cat <<'EOF'

       _     _              _
      (_)___| |_ ___   ___ | |__ ____
      | / __| __/ _ \ / _ \| '_ \_  /
      | \__ \ || (_) | (_) | |_) / /
     _/ |___/\__\___/ \___/|_.__/___|
    |__/
        By James Stephens (jstoobz)

EOF
printf "${RESET}"

# ── Sudo keepalive ──────────────────────────────────────────────────────────

sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ── Xcode CLT (provides git) ───────────────────────────────────────────────

if [ ! -f "/Library/Developer/CommandLineTools/usr/bin/git" ]; then
  echo "Installing Xcode Command Line Tools..."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  CLT=$(softwareupdate -l \
    | grep -B 1 "Command Line Tools" \
    | awk -F"*" '/^ *\*/ {print $2}' \
    | sed -e 's/^ *Label: //' -e 's/^ *//' \
    | sort -V | tail -n1)
  softwareupdate -i "$CLT"
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  echo "Xcode Command Line Tools installed"
fi

# ── Clone and install ───────────────────────────────────────────────────────

DOTFILES="${HOME}/dotfiles"
git clone https://github.com/jstoobz/dotfiles.git "$DOTFILES" 2>/dev/null \
  || (cd "$DOTFILES" && git pull)
exec "$DOTFILES/install" --from-step 2 "$@"
