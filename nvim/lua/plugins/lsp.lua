return {
  { 'neovim/nvim-lspconfig' },
  {
    'mason-org/mason.nvim',
    config = function()
      require('mason').setup({})
    end,
  },
  {
    'mason-org/mason-lspconfig.nvim',
    dependencies = {
      'mason-org/mason.nvim',
      'neovim/nvim-lspconfig',
    },
    config = function()
      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls',
          'ts_ls',
          'cssls',
          'html',
          'jsonls',
          'eslint',
          'vue_ls',
          'ruby_lsp',
          'elixirls'
        },
        automatic_enable = false,
      })

      local border = {
        {"🭽", "FloatBorder"},
        {"▔", "FloatBorder"},
        {"🭾", "FloatBorder"},
        {"▕", "FloatBorder"},
        {"🭿", "FloatBorder"},
        {" ", "FloatBorder"},
        {"🭼", "FloatBorder"},
        {"▏", "FloatBorder"},
      }

      -- Path to Vue TypeScript plugin for ts_ls integration
      local vue_typescript_plugin_path = vim.fn.stdpath('data') .. "/mason/packages/vue-language-server/node_modules/@vue/typescript-plugin"

      local vue_typescript_plugin = {
        name = '@vue/typescript-plugin',
        location = vue_typescript_plugin_path,
        languages = { 'vue' },
      }

      -- Define capabilities for nvim-cmp if it's available
      local capabilities = nil
      if pcall(require, 'cmp_nvim_lsp') then
        capabilities = require('cmp_nvim_lsp').default_capabilities()
      end

      -- Common on_attach function for LSP clients
      local lsp_attach = function(client, bufnr)
        local opts = {buffer = bufnr}
        vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
        vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
        vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
        vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
        vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', opts)
        vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)
        vim.keymap.set('n', '<F2>', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
        vim.keymap.set({'n', 'x'}, '<F3>', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)
        vim.keymap.set('n', '<F4>', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
      end

      -- Directly set global LSP handlers with border options
      local default_hover_handler = vim.lsp.handlers.hover
      vim.lsp.handlers["textDocument/hover"] = function(err, result, ctx, config)
        config = config or {}
        config.border = border
        return default_hover_handler(err, result, ctx, config)
      end

      local default_signature_help_handler = vim.lsp.handlers.signature_help
      vim.lsp.handlers["textDocument/signatureHelp"] = function(err, result, ctx, config)
        config = config or {}
        config.border = border
        return default_signature_help_handler(err, result, ctx, config)
      end

      -- ts_ls (TypeScript Language Server) configuration
      -- Adds 'vue' to filetypes so ts_ls attaches to .vue files (required for vue_ls v3 hybrid mode)
      vim.lsp.config('ts_ls', {
        capabilities = capabilities,
        filetypes = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'vue' },
        init_options = {
          plugins = {
            vue_typescript_plugin,
          },
        },
        on_attach = lsp_attach,
        root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' },
      })
      vim.lsp.enable('ts_ls')

      -- Vue Language Server v3 configuration (hybrid mode)
      -- The critical on_init handler that bridges vue_ls <-> ts_ls is provided by
      -- nvim-lspconfig's lsp/vue_ls.lua and merged automatically via vim.lsp.config()
      vim.lsp.config('vue_ls', {
        capabilities = capabilities,
        settings = {
          vue = {
            complete = {
              casing = {
                props = 'camelCase',
                tags = 'kebabCase',
              },
            },
          },
        },
        on_attach = lsp_attach,
        root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' },
      })
      vim.lsp.enable('vue_ls')

      -- Other server configurations
      vim.lsp.config('eslint', {
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      vim.lsp.enable('eslint')

      vim.lsp.config('jsonls', {
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      vim.lsp.enable('jsonls')

      vim.lsp.config('cssls', {
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      vim.lsp.enable('cssls')

      vim.lsp.config('html', {
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      vim.lsp.enable('html')

      -- lua_ls configuration
      vim.lsp.config('lua_ls', {
        capabilities = capabilities,
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
              special = {
                import = 'require',
              },
            },
            workspace = {
              checkThirdParty = false,
              library = vim.api.nvim_get_runtime_file("", true),
              maxPreload = 10000,
              preloadFileSize = 10000,
            },
            diagnostics = {
              globals = { 'vim', 'use', 'fs_stat' },
            },
            completion = {
              callSnippet = 'Replace',
              keywordSnippet = 'Replace',
            },
            hint = {
              enable = true,
              setType = true,
            },
            telemetry = {
              enable = false,
            },
          },
        },
        on_attach = lsp_attach,
      })
      vim.lsp.enable('lua_ls')

      vim.lsp.config('ruby_lsp', {
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      vim.lsp.enable('ruby_lsp')

      -- Elixir LS configuration
      vim.lsp.config('elixirls', {
        capabilities = capabilities,
        cmd = { vim.fn.stdpath("data") .. "/mason/packages/elixir-ls/language_server.sh" },
        settings = {
          elixirLS = {
            dialyzerEnabled = false,
            fetchDeps = false,
            enableTestLenses = false,
            suggestSpecs = false,
          }
        },
        on_attach = lsp_attach,
        root_markers = { 'mix.exs', '.git' },
      })
      vim.lsp.enable('elixirls')
    end
  },
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    dependencies = { 'mason-org/mason.nvim' },
  },
}
