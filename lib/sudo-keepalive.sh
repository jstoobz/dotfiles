#!/bin/sh
# ============================================================================
# Sudo session keepalive
# Ask once, then refresh in background until parent script exits
# ============================================================================

ask_for_sudo() {
  sudo -v

  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null &
}
