-- colorscheme
return {
  -- {
  --   -- Definitely I want to use them...
  --   -- but it can't be reflect on my terminal when starting up nvim.
  --   'rebelot/kanagawa.nvim',
  --   lazy = false,
  --   priority = 1000,
  --   config = function()
  --     vim.cmd([[colorscheme kanagawa-wave]])
  --   end,
  -- },
  {
    'blueshirts/darcula',
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd([[colorscheme darcula]])
    end,
  },
}
