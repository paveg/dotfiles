-- Claude Code integration for Neovim
---@type LazySpec
return {
  {
    "coder/claudecode.nvim",
    lazy = false,
    config = function()
      require("claudecode").setup({
        -- You can customize options here if needed
        -- For example:
        -- keymaps = {
        --   chat = "<leader>cc",
        --   generate = "<leader>cg",
        -- }
      })
    end,
    keys = {
      { "<leader>cc", "<cmd>ClaudeCodeChat<cr>", desc = "Claude Code Chat" },
      { "<leader>cg", "<cmd>ClaudeCodeGenerate<cr>", desc = "Claude Code Generate" },
      { "<leader>cr", "<cmd>ClaudeCodeReview<cr>", desc = "Claude Code Review" },
      { "<leader>ce", "<cmd>ClaudeCodeExplain<cr>", desc = "Claude Code Explain" },
    },
  },
}