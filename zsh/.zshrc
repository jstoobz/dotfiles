# ============================================================================
# ZSH Configuration
# ~/.zshrc - Loaded for interactive shells
# ============================================================================

# Performance profiling (uncomment to debug slow startup)
# zmodload zsh/zprof

# ============================================================================
# Environment Variables
# ============================================================================

export EDITOR="code -w"
export VISUAL="code -w"
export PAGER="less"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# XDG Base Directories
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"

# Dotfiles location
export DOTFILES="${HOME}/.dotfiles"

# History
export HISTFILE="${HOME}/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000

# Less options
export LESS="-R -F -X"
export LESSHISTFILE="-"

# ============================================================================
# Path Configuration
# ============================================================================

# Function to add to PATH if not already present
path_prepend() {
    [[ -d "$1" ]] && path=("$1" $path)
}

path_append() {
    [[ -d "$1" ]] && path+=("$1")
}

# Homebrew (Apple Silicon)
if [[ -d "/opt/homebrew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# User binaries
path_prepend "${HOME}/.local/bin"
path_prepend "${HOME}/bin"

# PostgreSQL 17
path_prepend "/opt/homebrew/opt/postgresql@17/bin"
path_prepend "/opt/homebrew/opt/libpq/bin"

# Export path
export PATH

# ============================================================================
# Zsh Options
# ============================================================================

# History
setopt EXTENDED_HISTORY          # Record timestamp
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicates first
setopt HIST_IGNORE_DUPS          # Don't record duplicates
setopt HIST_IGNORE_ALL_DUPS      # Remove older duplicate
setopt HIST_IGNORE_SPACE         # Don't record space-prefixed commands
setopt HIST_FIND_NO_DUPS         # No duplicates in search
setopt HIST_SAVE_NO_DUPS         # Don't save duplicates
setopt SHARE_HISTORY             # Share history between sessions
setopt INC_APPEND_HISTORY        # Add immediately

# Directory
setopt AUTO_CD                   # cd by typing directory name
setopt AUTO_PUSHD                # Push directories onto stack
setopt PUSHD_IGNORE_DUPS         # No duplicate directories
setopt PUSHD_SILENT              # Don't print stack

# Completion
setopt COMPLETE_IN_WORD          # Complete from both ends
setopt ALWAYS_TO_END             # Move cursor to end
setopt MENU_COMPLETE             # Autoselect first completion
setopt AUTO_MENU                 # Show menu on tab

# Misc
setopt INTERACTIVE_COMMENTS      # Allow comments in interactive
setopt NO_BEEP                   # No beeping
setopt CORRECT                   # Spelling correction
setopt EXTENDED_GLOB             # Extended globbing

# ============================================================================
# Completion System
# ============================================================================

# Initialize completion
autoload -Uz compinit

# Only check cache once per day
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# Completion options
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'
zstyle ':completion:*:corrections' format '%B%d (errors: %e)%b'
zstyle ':completion:*' group-name ''

# ============================================================================
# ASDF Version Manager
# ============================================================================

if [[ -f "$(brew --prefix asdf)/libexec/asdf.sh" ]]; then
    source "$(brew --prefix asdf)/libexec/asdf.sh"
fi

# ============================================================================
# Tool Initializations
# ============================================================================

# Zoxide (better cd)
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# FZF
if [[ -f "${HOME}/.fzf.zsh" ]]; then
    source "${HOME}/.fzf.zsh"
fi

# FZF configuration
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS="
  --height 40%
  --layout=reverse
  --border
  --preview 'bat --style=numbers --color=always --line-range :200 {}'
  --preview-window=right:60%:wrap
"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# Direnv
if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi

# Starship prompt
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

# ============================================================================
# Zsh Plugins (via Homebrew)
# ============================================================================

# Autosuggestions
if [[ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Syntax highlighting (must be last)
if [[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# ============================================================================
# Load Custom Configuration
# ============================================================================

# Load aliases
if [[ -f "${XDG_CONFIG_HOME}/zsh/aliases.zsh" ]]; then
    source "${XDG_CONFIG_HOME}/zsh/aliases.zsh"
fi

# Load functions
if [[ -f "${XDG_CONFIG_HOME}/zsh/functions.zsh" ]]; then
    source "${XDG_CONFIG_HOME}/zsh/functions.zsh"
fi

# Load local configuration (machine-specific, not in git)
if [[ -f "${HOME}/.zshrc.local" ]]; then
    source "${HOME}/.zshrc.local"
fi

# ============================================================================
# End of Configuration
# ============================================================================

# Uncomment to see startup profiling
# zprof
