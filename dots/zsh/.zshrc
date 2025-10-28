if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
    tmux attach -t default || tmux new -s default
fi

ZSH_THEME="random"
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

# Path to your oh-my-zsh installation.
export PATH="$HOME/.local/bin:$HOME/.local/pipx/bin:$HOME/go/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

zstyle ':omz:update' mode auto      # update automatically without asking

# Uncomment the following line if pasting URLs and other text is messed up.
DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load?
# Plugins
# https://github.com/zshzoo/cd-ls
# https://github.com/alexiszamanidis/zsh-git-fzf
# https://github.com/jeffreytse/zsh-vi-mode
# https://github.com/djui/alias-tips
# https://github.com/thirteen37/fzf-alias
# https://github.com/zsh-users/zsh-history-substring-search
# https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md
# https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.m

# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
[[ -z "${plugins[*]}" ]] && plugins=(git fzf extract gitignore pip python docker docker-compose zsh-vi-mode cd-ls zsh-git-fzf alias-tips ufw themes fzf-alias zsh-history-substring-search zsh-syntax-highlighting zsh-autosuggestions archlinux zsh-aur-install)

if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi
source $HOME/.aliases

# User configuration

# HIST_STAMPS="dd.mm.yyyy"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Ignore commands that start with spaces and duplicates.

export HISTCONTROL=ignoreboth

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Don't add certain commands to the history file.

export HISTIGNORE="&:[bf]g:c:clear:history:exit:q:pwd:* --help"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Use custom `less` colors for `man` pages.

export LESS_TERMCAP_md="$(tput bold 2> /dev/null; tput setaf 2 2> /dev/null)"
export LESS_TERMCAP_me="$(tput sgr0 2> /dev/null)"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Make new shells get the history lines from all previous
# shells instead of the default "last window closed" history.

export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd zsh)"
fi

# FZF
export FZF_BASE=/usr/share/fzf
export FZF_DEFAULT_OPTS='--reverse --preview="bat {}" --info=inline --color=fg:#f8f8f2,bg:-1,hl:#bd93f9 --color=fg+:#f8f8f2,bg+:-1,gutter:-1,hl+:#bd93f9 --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4'
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# Loads FZF keybindings, replacing native reverse search etc with FZF
[[ -e "/usr/share/fzf/key-bindings.zsh" ]] \
  && source "/usr/share/fzf/key-bindings.zsh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# bat 

# bat can be used as a colorizing pager for man, by setting the MANPAGER environment variable:
export MANPAGER="sh -c 'awk '\''{ gsub(/\x1B\[[0-9;]*m/, \"\", \$0); gsub(/.\x08/, \"\", \$0); print }'\'' | bat -p -lman'"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# node fnm
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  source "$NVM_DIR/nvm.sh"
  if [[ -s "$NVM_DIR/bash_completion" ]]; then
    source "$NVM_DIR/bash_completion"
  fi
fi
