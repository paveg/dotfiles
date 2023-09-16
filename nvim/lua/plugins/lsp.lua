return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      'lvimuser/lsp-inlayhints.nvim',
      'hrsh7th/nvim-cmp',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/vim-vsnip'
    },
    config = function()
      require('mason').setup {}
      require('mason-lspconfig').setup_handlers({ function(server)
        local opt = {
          capabilities = require('cmp_nvim_lsp').default_capabilities(
            vim.lsp.protocol.make_client_capabilities()
          )
        }
        require('lspconfig')[server].setup(opt)
      end })
      vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', { noremap = true, silent = true })
    end,
  },
  {
    'nvim-lua/lsp-status.nvim',
    config = function ()
      local lsp_status = require('lsp-status')
      lsp_status.config {
        status_symbol = '',
        indicator_errors = '',
        indicator_warnings = '',
        indicator_info = '',
        indicator_hint = '',
        indicator_ok = '',
        current_function = false,
      }
      lsp_status.register_progress()
    end,
  }
}
