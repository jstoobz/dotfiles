# Tmux Plugins — Reference

Curated list of plugins to add when you outgrow the base config.

## Getting Started

Install **tpm** first (Tmux Plugin Manager), then add plugins to `.tmux.conf`.

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then `prefix + I` to install plugins listed in your config.

## Plugin Reference

| Plugin | What it does |
|---|---|
| [tpm](https://github.com/tmux-plugins/tpm) | Tmux Plugin Manager — install/update/remove plugins |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | Save/restore sessions across tmux server restarts |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | Auto-save sessions every 15 min, auto-restore on start |
| [tmux-yank](https://github.com/tmux-plugins/tmux-yank) | System clipboard integration for copy mode |
| [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible) | Community-agreed defaults (we already cover most of these) |
| [catppuccin/tmux](https://github.com/catppuccin/tmux) | Match your Neovim theme in the status bar |
| [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) | Seamless Ctrl+hjkl between tmux and Neovim (tmux side) |
| [tmux-sessionizer](https://github.com/jrmoulton/tmux-sessionizer) | Quick-switch between project sessions with fzf |

## Suggested Install Order

1. **tpm** — needed to install everything else
2. **vim-tmux-navigator** — if using Neovim (install both tmux and Neovim sides)
3. **tmux-resurrect** — peace of mind for session persistence
4. **catppuccin/tmux** — match your editor theme
5. Everything else as needed
