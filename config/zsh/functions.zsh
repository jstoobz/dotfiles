# ============================================================================
# Shell Functions
# ~/.config/zsh/functions.zsh
# ============================================================================

# ============================================================================
# Directory Operations
# ============================================================================

# Create directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Create a temporary directory and cd into it
tmpcd() {
  cd "$(mktemp -d)"
}

# Go up N directories
up() {
  local d=""
  limit="${1:-1}"
  for ((i = 1; i <= limit; i++)); do
    d="../$d"
  done
  cd "$d" || return 1
}

# ============================================================================
# File Operations
# ============================================================================

# Extract any archive
extract() {
  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz) tar xzf "$1" ;;
      *.tar.xz) tar xJf "$1" ;;
      *.bz2) bunzip2 "$1" ;;
      *.gz) gunzip "$1" ;;
      *.tar) tar xf "$1" ;;
      *.tbz2) tar xjf "$1" ;;
      *.tgz) tar xzf "$1" ;;
      *.zip) unzip "$1" ;;
      *.Z) uncompress "$1" ;;
      *.7z) 7z x "$1" ;;
      *) echo "'$1' cannot be extracted" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Create a tar.gz archive
targz() {
  local tmpFile="${1%/}.tar"
  tar -cvf "${tmpFile}" --exclude=".DS_Store" "${1}" || return 1

  local size
  size=$(stat -f"%z" "${tmpFile}" 2>/dev/null || stat -c"%s" "${tmpFile}" 2>/dev/null)

  gzip -f "${tmpFile}" || return 1
  echo "${tmpFile}.gz created successfully"
}

# Quick backup of a file
backup() {
  cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
}

# ============================================================================
# Development
# ============================================================================

# Create a new Phoenix project with my preferred settings
phx_new() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: phx_new <project_name>"
    return 1
  fi

  mix phx.new "$name" \
    --database postgres \
    --binary-id \
    --no-dashboard \
    --no-mailer

  cd "$name" || return 1
  echo ""
  echo "Project created! Run:"
  echo "  mix setup"
  echo "  mix phx.server"
}

# Format and test
mft() {
  mix format && mix test "$@"
}

# Compile and check for warnings as errors
mcw() {
  mix compile --warnings-as-errors "$@"
}

# ============================================================================
# Git
# ============================================================================

# Create a new branch from main
gnb() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "Usage: gnb <branch_name>"
    return 1
  fi
  git checkout main && git pull && git checkout -b "$branch"
}

# Interactive rebase on main
grim() {
  local count="${1:-10}"
  git rebase -i HEAD~"$count"
}

# Git commit with message
gcmsg() {
  git commit -m "$*"
}

# Checkout to previous branch
gprev() {
  git checkout -
}

# Pretty git log
glog() {
  git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit "$@"
}

# Clone and cd into repo
gclone() {
  git clone "$1" && cd "$(basename "$1" .git)" || return 1
}

# ============================================================================
# Docker
# ============================================================================

# Stop all running containers
dstopall() {
  docker stop $(docker ps -q) 2>/dev/null
}

# Remove all stopped containers
drmall() {
  docker rm $(docker ps -a -q) 2>/dev/null
}

# Remove all images
drmiall() {
  docker rmi $(docker images -q) 2>/dev/null
}

# Enter a running container
dexec() {
  docker exec -it "$1" /bin/bash
}

# Build and run docker-compose
dcup() {
  docker compose up --build "$@"
}

# ============================================================================
# Network
# ============================================================================

# Get public IP
myip() {
  echo "Public IP: $(curl -s ifconfig.me)"
  echo "Local IP:  $(ipconfig getifaddr en0 2>/dev/null || echo 'N/A')"
}

# Scan local network
netscan() {
  local subnet="${1:-192.168.1.0/24}"
  nmap -sn "$subnet"
}

# Check if a port is open
portcheck() {
  local host="${1:-localhost}"
  local port="$2"
  if [[ -z "$port" ]]; then
    echo "Usage: portcheck <host> <port>"
    return 1
  fi
  nc -zv "$host" "$port"
}

# ============================================================================
# macOS
# ============================================================================

# Show notification
notify() {
  osascript -e "display notification \"$*\" with title \"Terminal\""
}

# Quick look from terminal
ql() {
  qlmanage -p "$@" &>/dev/null
}

# Open man page as PDF in Preview
manpdf() {
  man -t "$1" | open -f -a Preview
}

# Rebuild Spotlight index
spotrebuild() {
  sudo mdutil -E /
}

# ============================================================================
# Text Processing
# ============================================================================

# Trim whitespace
trim() {
  awk '{$1=$1};1'
}

# Count lines in files
lc() {
  wc -l "$@" | sort -rn
}

# Search and replace in files
replace() {
  if [[ $# -lt 3 ]]; then
    echo "Usage: replace <find> <replace> <file(s)>"
    return 1
  fi
  local find="$1"
  local replace="$2"
  shift 2

  if command -v sd &>/dev/null; then
    sd "$find" "$replace" "$@"
  else
    sed -i '' "s/$find/$replace/g" "$@"
  fi
}

# ============================================================================
# Utilities
# ============================================================================

# Calculator
calc() {
  echo "scale=2; $*" | bc
}

# Generate a random password
genpass() {
  local length="${1:-32}"
  openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()' | head -c"$length"
  echo
}

# Show color palette
colors() {
  for i in {0..255}; do
    printf "\x1b[38;5;${i}m%3d\e[0m " "$i"
    if (((i + 1) % 16 == 0)); then
      printf "\n"
    fi
  done
}

# URL encode/decode
urlencode() {
  python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))"
}

urldecode() {
  python3 -c "import urllib.parse; print(urllib.parse.unquote('$1'))"
}

# JSON pretty print from clipboard
jsonclip() {
  pbpaste | jq .
}

# Get weather for a location
wttr() {
  local location="${1:-}"
  curl -s "wttr.in/${location}?format=v2"
}

# ============================================================================
# Elixir/Erlang
# ============================================================================

# Observer (Erlang GUI)
observer() {
  iex -e ":observer.start()"
}

# Connect to running Phoenix app
remsh() {
  local cookie="${1:-cookie}"
  local node="${2:-app@127.0.0.1}"
  iex --name "console@127.0.0.1" --cookie "$cookie" --remsh "$node"
}

# ============================================================================
# FZF Integration
# ============================================================================

# fzf + git log
fgl() {
  git log --oneline --decorate --color | fzf --ansi --preview 'git show --color=always {+1}' | awk '{print $1}'
}

# fzf + git branch
fbr() {
  git branch -a --color | fzf --ansi | sed 's/^\*//;s/^ *//' | xargs git checkout
}

# fzf + process kill
fkill() {
  local pid
  pid=$(ps aux | fzf --header='Select process to kill' | awk '{print $2}')
  if [[ -n "$pid" ]]; then
    echo "Killing PID: $pid"
    kill -9 "$pid"
  fi
}

# fzf + cd to directory
fcd() {
  local dir
  dir=$(fd --type d --hidden --follow --exclude .git | fzf --preview 'eza -la --color=always {}')
  if [[ -n "$dir" ]]; then
    cd "$dir" || return 1
  fi
}

# fzf + edit file
fe() {
  local file
  file=$(fd --type f --hidden --follow --exclude .git | fzf --preview 'bat --style=numbers --color=always {}')
  if [[ -n "$file" ]]; then
    ${EDITOR:-vim} "$file"
  fi
}
