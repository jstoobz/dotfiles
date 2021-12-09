export PATH="/usr/local/sbin:$PATH"

export ZSH="${HOME}/.oh-my-zsh"

ZSH_THEME="robbyrussell"

DISABLE_AUTO_UPDATE="true"

plugins=(git)

FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"

source $ZSH/oh-my-zsh.sh

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

export HOMEBREW_NO_ANALYTICS=1

export HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTCONTROL=ignoreboth

setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_SPACE
setopt NO_CASE_GLOB
setopt GLOB_COMPLETE
setopt AUTO_CD

export EDITOR=vim
export TERM=xterm-256color

export PAGER="less"
export MANPAGER="less -X"

export GPG_TTY=$(tty)

export ERL_AFLAGS="-kernel shell_history enabled"

export KERL_CONFIGURE_OPTIONS="--without-javac --with-ssl=$(brew --prefix openssl)"
export KERL_BUILD_DOCS="yes"
export KERL_INSTALL_HTMLDOCS="yes"
export KERL_INSTALL_MANPAGES="yes"

. $(brew --prefix asdf)/libexec/asdf.sh

. $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

. $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh