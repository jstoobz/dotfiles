-- ============================================================================
-- Neovim — Barebones config (zero plugins)
-- ============================================================================

-- Leader key (must be set before any mappings)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable netrw banner (keep netrw itself as file explorer)
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3

-- ============================================================================
-- Options
-- ============================================================================

local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

-- Indentation (2 spaces — Elixir/web conventions)
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

-- System clipboard
opt.clipboard = "unnamedplus"

-- Splits
opt.splitright = true
opt.splitbelow = true

-- Scrolling
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Persistent undo (survives closing the file)
opt.undofile = true

-- Visual
opt.cursorline = true
opt.signcolumn = "yes"
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
opt.termguicolors = true
opt.showmode = false

-- Wrapping
opt.wrap = false
opt.breakindent = true

-- Completion
opt.completeopt = { "menuone", "noselect" }

-- Misc
opt.updatetime = 250
opt.timeoutlen = 300
opt.mouse = "a"
opt.confirm = true

-- ============================================================================
-- Keymaps
-- ============================================================================

local map = vim.keymap.set

-- Save / quit
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })

-- Clear search highlights
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

-- File explorer (netrw)
map("n", "<leader>e", "<cmd>Explore<cr>", { desc = "File explorer" })

-- Window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Move to left split" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower split" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper split" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right split" })

-- Move selected lines up/down in visual mode
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Keep cursor centered when scrolling
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

-- Keep cursor centered when searching
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Better paste (don't overwrite register)
map("x", "<leader>p", '"_dP', { desc = "Paste without overwriting register" })

-- ============================================================================
-- Autocommands
-- ============================================================================

local au = vim.api.nvim_create_augroup("UserConfig", { clear = true })

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = au,
  callback = function()
    vim.highlight.on_yank({ timeout = 200 })
  end,
})

-- Remove trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
  group = au,
  pattern = "*",
  command = [[%s/\s\+$//e]],
})
