# Neovim Plugins — Reference

Curated list of plugins to add incrementally. Start with the base config,
then pick from here when you hit a real need.

## Getting Started

Install **lazy.nvim** first, then add plugins one at a time.

## Plugin Reference

| Category | Plugin | What it does |
|---|---|---|
| **Package Manager** | [lazy.nvim](https://github.com/folke/lazy.nvim) | Modern plugin manager with lazy-loading and lockfile |
| **Fuzzy Finding** | [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Find files, grep text, search anything with fzf-style UI |
| **File Tree** | [oil.nvim](https://github.com/stevearc/oil.nvim) | Edit filesystem like a buffer (mkdir, rename, delete as text) |
| **LSP** | [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | Configure built-in LSP for Elixir, TypeScript, etc. |
| **Completion** | [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | Autocompletion from LSP, snippets, buffer |
| **Syntax** | [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Better highlighting, text objects, code folding |
| **Git** | [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git hunks in sign column, inline blame |
| **Git** | [fugitive.vim](https://github.com/tpope/vim-fugitive) | Git commands inside Neovim (`:Git blame`, `:Git log`) |
| **Theme** | [catppuccin](https://github.com/catppuccin/nvim) | Warm pastel theme, well-maintained |
| **Theme** | [tokyonight](https://github.com/folke/tokyonight.nvim) | Clean dark theme with multiple variants |
| **Status Line** | [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | Configurable status bar with mode, branch, diagnostics |
| **Navigation** | [harpoon](https://github.com/ThePrimeagen/harpoon/tree/harpoon2) | Pin and jump between files instantly |
| **Surround** | [mini.surround](https://github.com/echasnovski/mini.surround) | Add/change/delete surrounding chars (quotes, brackets) |
| **Pairs** | [mini.pairs](https://github.com/echasnovski/mini.pairs) | Auto-close brackets, quotes |
| **Comments** | [mini.comment](https://github.com/echasnovski/mini.comment) | Toggle comments with `gc` |
| **Tmux** | [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) | Seamless Ctrl+hjkl between tmux panes and Neovim splits |

## Suggested Install Order

1. **lazy.nvim** — needed to install everything else
2. **telescope.nvim** — immediate productivity boost (find files, grep)
3. **nvim-treesitter** — better syntax highlighting
4. **nvim-lspconfig** + **nvim-cmp** — language intelligence
5. **gitsigns.nvim** — see changes in the gutter
6. **catppuccin** or **tokyonight** — make it look good
7. Everything else as needed
