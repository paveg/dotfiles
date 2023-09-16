-- encoding
vim.o.encoding = 'utf-8'
vim.scriptencoding = 'utf-8'

-- visual
vim.o.ambiwidth = 'double'
vim.o.tabstop = 2
vim.o.softabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = true
vim.o.autoindent = true
vim.o.smartindent = true
vim.o.number = true
vim.o.showmatch = true
vim.o.matchtime = 1

-- search
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = true
vim.o.incsearch = true

-- manipulation
vim.g.mapleader = ' '
vim.opt.clipboard:append{'unnamedplus'}
vim.o.ttimeout = true
vim.o.ttimeoutlen = 50
vim.o.undofile = true
vim.o.undodir = vim.fn.stdpath('cache') .. '/undo'

-- keymap
-- @see https://qiita.com/t_uda/items/407220bfc989f901baf5
vim.api.nvim_set_keymap('n', '<Esc><Esc>', ':nohl<CR>', {
    noremap = true,
    silent = true
})
vim.api.nvim_set_keymap('n', 'j', 'gj', {
    noremap = true
})
vim.api.nvim_set_keymap('n', '<Down>', 'gj', {
    noremap = true
})
vim.api.nvim_set_keymap('n', '<Up>', 'gk', {
    noremap = true
})
vim.api.nvim_set_keymap('n', 'gj', 'j', {
    noremap = true
})
vim.api.nvim_set_keymap('n', 'gk', 'k', {
    noremap = true
})

-- load lazy.nvim
require('lazy-nvim')
