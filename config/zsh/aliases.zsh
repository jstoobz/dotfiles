# ============================================================================
# Zsh Aliases
# ~/.config/zsh/aliases.zsh
# ============================================================================

# ============================================================================
# Navigation
# ============================================================================

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias ~='cd ~'
alias -- -='cd -'

# Quick access (customize to your directories)
alias dot='cd ${DOTFILES:-~/.dotfiles}'
alias dl='cd ~/Downloads'
alias proj='cd ~/projects'

# ============================================================================
# Directory Listing (using eza if available, else ls)
# ============================================================================

if command -v eza &>/dev/null; then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --group-directories-first --git'
  alias la='eza -la --group-directories-first --git'
  alias lt='eza -T --group-directories-first --level=2'
  alias lta='eza -Ta --group-directories-first --level=2'
else
  alias ls='ls --color=auto'
  alias ll='ls -lh'
  alias la='ls -lah'
fi

# ============================================================================
# File Operations (with safety)
# ============================================================================

alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias mkdir='mkdir -pv'

# ============================================================================
# Common Commands
# ============================================================================

alias c='clear'
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%Y-%m-%d %H:%M:%S"'

# Grep with color
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Disk usage
alias df='df -h'
alias du='du -h'
alias dud='du -d 1 -h'
alias duf='du -sh *'


# ============================================================================
# Editor
# ============================================================================

alias e='${EDITOR}'
alias edit='${EDITOR}'
alias zshrc='${EDITOR} ~/.zshrc'
alias aliases='${EDITOR} ${XDG_CONFIG_HOME}/zsh/aliases.zsh'

# ============================================================================
# Git
# ============================================================================

alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gplr='git pull --rebase'
alias gf='git fetch'
alias gfa='git fetch --all --prune'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline -20'
alias gla='git log --oneline --all --graph -20'
alias glg='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias grs='git reset'
alias grsh='git reset --hard'
alias gchp='git cherry-pick'
alias gm='git merge'
alias gclean='git clean -fd'
alias gwip='git add -A && git commit -m "WIP"'
alias gunwip='git log -1 --format="%s" | grep -q "WIP" && git reset HEAD~1'

# ============================================================================
# Elixir / Phoenix
# ============================================================================

alias m='mix'
alias mt='mix test'
alias mtw='mix test.watch'
alias mf='mix format'
alias mc='mix compile'
alias mdg='mix deps.get'
alias mdc='mix deps.compile'
alias mdu='mix deps.update --all'
alias mpr='mix phx.routes'
alias mps='mix phx.server'
alias ism='iex -S mix'
alias ismp='iex -S mix phx.server'
alias mec='mix ecto.create'
alias mem='mix ecto.migrate'
alias mer='mix ecto.rollback'
alias mes='mix ecto.setup'
alias mesd='mix ecto.seed'
alias mers='mix ecto.reset'
alias megen='mix ecto.gen.migration'

# ============================================================================
# Docker
# ============================================================================

alias d='docker'
alias dc='docker compose'
alias dcu='docker compose up'
alias dcud='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs'
alias dclf='docker compose logs -f'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias drmi='docker rmi'
alias dprune='docker system prune -af'

# ============================================================================
# PostgreSQL
# ============================================================================

alias pg='psql -U postgres'
alias pgstart='brew services start postgresql'
alias pgstop='brew services stop postgresql'
alias pgrestart='brew services restart postgresql'
alias pgstatus='brew services info postgresql'

# ============================================================================
# Homebrew
# ============================================================================

alias b='brew'
alias bi='brew install'
alias bic='brew install --cask'
alias bu='brew update'
alias bug='brew upgrade'
alias bo='brew outdated'
alias bc='brew cleanup'
alias bs='brew search'
alias binfo='brew info'
alias blist='brew list'
alias bservices='brew services list'

# ============================================================================
# Network
# ============================================================================

alias ip='curl -s ipinfo.io/ip'
alias localip='ipconfig getifaddr en0'
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"
alias ports='lsof -iTCP -sTCP:LISTEN -n -P'
alias ping='ping -c 5'
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'

# ============================================================================
# macOS Specific
# ============================================================================

alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias emptytrash='rm -rf ~/.Trash/*'
alias afk='pmset displaysleepnow'

# ============================================================================
# Claude Code
# ============================================================================

# Subscription plan (OAuth authentication)
alias claude-sub='claude'

# Direct API billing (per-token)
alias claude-api='ANTHROPIC_API_KEY="$(< ~/.config/anthropic/api_key)" claude'

# ============================================================================
# Quick Edits / Reload
# ============================================================================

alias reload='source ~/.zshrc && echo "ZSH config reloaded"'
alias reloadall='exec zsh'

# ============================================================================
# Misc Utilities
# ============================================================================

# Weather
alias weather='curl -s "wttr.in?format=3"'
alias weatherfull='curl -s "wttr.in"'

# Generate random password
alias randpw='openssl rand -base64 24'

# URL encode/decode
alias urlencode='python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))"'
alias urldecode='python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))"'

# JSON pretty print
alias jsonpp='python3 -m json.tool'

# Serve current directory
alias serve='python3 -m http.server 8000'


# ============================================================================
# End of Aliases
# ============================================================================
